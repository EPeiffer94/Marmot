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
    private static let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=200000000")!
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

/// Times a transfer, cancelling once the cap elapses, and reports Mbps from
/// whatever moved in that window. Works for fast and slow lines alike.
private final class ThroughputProbe: NSObject, URLSessionDataDelegate {

    private let cap: TimeInterval
    private var transferred: Int64 = 0
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
        let payload = Data(count: 64 * 1024 * 1024) // plenty; the cap cuts it short
        return try await withCheckedThrowingContinuation { continuation in
            probe.begin(continuation: continuation) { session in
                session.uploadTask(with: request, from: payload)
            }
        }
    }

    private func begin(continuation: CheckedContinuation<Double, Error>,
                       makeTask: (URLSession) -> URLSessionTask) {
        self.continuation = continuation
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
        session?.invalidateAndCancel()
        session = nil
    }

    private var currentRate: Double {
        let elapsed = max(Date().timeIntervalSince(started), 0.1)
        return Double(transferred) * 8 / elapsed / 1_000_000
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
        transferred = totalBytesSent
        if Date().timeIntervalSince(started) >= cap {
            let rate = currentRate
            task.cancel()
            finish(with: .success(rate))
        }
    }

    // MARK: Completion (natural finish, cancellation, or failure)

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error, (error as NSError).code != NSURLErrorCancelled, transferred == 0 {
            finish(with: .failure(error))
        } else {
            finish(with: .success(currentRate))
        }
    }
}
