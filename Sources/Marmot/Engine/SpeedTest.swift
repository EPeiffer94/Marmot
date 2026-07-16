import Foundation

/// Lightweight network speed test against Cloudflare's public speed servers
/// (speed.cloudflare.com — no account, no API key). Transfers are capped at
/// ~8 seconds each, so the whole test finishes in well under half a minute.
final class SpeedTest: ObservableObject {

    enum Phase: Equatable {
        case idle
        case pinging
        case downloading
        case uploading
        case done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pingMS: Double?
    @Published private(set) var downloadMbps: Double?
    @Published private(set) var uploadMbps: Double?

    private static let pingURL = URL(string: "https://speed.cloudflare.com/__down?bytes=1")!
    // Cloudflare caps __down somewhere between 50 and 100 MB — stay safely
    // under it; the probe loops requests until its time cap anyway.
    private static let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=50000000")!
    private static let uploadURL = URL(string: "https://speed.cloudflare.com/__up")!

    var isRunning: Bool {
        switch phase {
        case .pinging, .downloading, .uploading: return true
        default: return false
        }
    }

    func run() {
        guard !isRunning else { return }
        Task { @MainActor in
            pingMS = nil
            downloadMbps = nil
            uploadMbps = nil
            do {
                phase = .pinging
                pingMS = try await Self.measurePing()
                phase = .downloading
                downloadMbps = try await ThroughputProbe.download(from: Self.downloadURL, cap: 8)
                phase = .uploading
                uploadMbps = try await ThroughputProbe.upload(to: Self.uploadURL, cap: 8)
                phase = .done
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Best of four tiny fetches — approximates round-trip latency.
    private static func measurePing() async throws -> Double {
        var best = Double.infinity
        for _ in 0..<4 {
            let start = Date()
            _ = try await URLSession.shared.data(from: pingURL)
            best = min(best, Date().timeIntervalSince(start) * 1000)
        }
        return best
    }
}

/// Times transfers, looping requests until the cap elapses, and reports Mbps
/// from everything moved in that window. Looping keeps the measurement
/// accurate on fast lines even though the server caps per-request sizes.
private final class ThroughputProbe: NSObject, URLSessionDataDelegate {

    private let cap: TimeInterval
    private var makeTask: ((URLSession) -> URLSessionTask)?
    private var transferred: Int64 = 0
    private var transferredBeforeCurrentTask: Int64 = 0
    private var started = Date()
    private var continuation: CheckedContinuation<Double, Error>?
    private var finished = false
    private var session: URLSession?

    private init(cap: TimeInterval) {
        self.cap = cap
    }

    static func download(from url: URL, cap: TimeInterval) async throws -> Double {
        let probe = ThroughputProbe(cap: cap)
        return try await withCheckedThrowingContinuation { continuation in
            probe.begin(continuation: continuation) { session in
                session.dataTask(with: url)
            }
        }
    }

    static func upload(to url: URL, cap: TimeInterval) async throws -> Double {
        let probe = ThroughputProbe(cap: cap)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let payload = Data(count: 16 * 1024 * 1024) // accepted by the server; looped
        return try await withCheckedThrowingContinuation { continuation in
            probe.begin(continuation: continuation) { session in
                session.uploadTask(with: request, from: payload)
            }
        }
    }

    private func begin(continuation: CheckedContinuation<Double, Error>,
                       makeTask: @escaping (URLSession) -> URLSessionTask) {
        self.continuation = continuation
        self.makeTask = makeTask
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: queue)
        self.session = session
        started = Date()
        makeTask(session).resume()
    }

    /// Resume exactly once, then tear the session down.
    private func finish(with result: Result<Double, Error>) {
        guard !finished else { return }
        finished = true
        switch result {
        case .success(let mbps): continuation?.resume(returning: mbps)
        case .failure(let error): continuation?.resume(throwing: error)
        }
        continuation = nil
        makeTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private var currentRate: Double {
        let elapsed = max(Date().timeIntervalSince(started), 0.1)
        return Double(transferred) * 8 / elapsed / 1_000_000
    }

    // MARK: Response guard — a refusal must be an error, never "0 Mbps"

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            completionHandler(.cancel)
            finish(with: .failure(NSError(
                domain: "SpeedTest", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Speed server refused (HTTP \(http.statusCode))."])))
            return
        }
        completionHandler(.allow)
    }

    // MARK: Download progress

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        transferred += Int64(data.count)
        if Date().timeIntervalSince(started) >= cap {
            let rate = currentRate
            dataTask.cancel()
            finish(with: .success(rate))
        }
    }

    // MARK: Upload progress

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        transferred = transferredBeforeCurrentTask + totalBytesSent
        if Date().timeIntervalSince(started) >= cap {
            let rate = currentRate
            task.cancel()
            finish(with: .success(rate))
        }
    }

    // MARK: Completion — loop another request if time remains

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard !finished else { return }

        if let error, (error as NSError).code != NSURLErrorCancelled {
            if transferred > 0 {
                finish(with: .success(currentRate))
            } else {
                finish(with: .failure(error))
            }
            return
        }

        let madeProgress = transferred > transferredBeforeCurrentTask
        if Date().timeIntervalSince(started) < cap, madeProgress, let makeTask {
            // Chunk finished early — keep the clock running with another one.
            transferredBeforeCurrentTask = transferred
            makeTask(session).resume()
        } else {
            finish(with: .success(currentRate))
        }
    }
}
