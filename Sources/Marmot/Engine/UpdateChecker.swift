import Foundation

struct AppUpdate: Identifiable {
    let id: String            // bundle path
    let appName: String
    let installedVersion: String
    let latestVersion: String
    let channel: String       // "Homebrew", "Sparkle", "App Store"
    let howToUpdate: String
}

/// Best-effort update detection across three channels:
/// 1. Homebrew casks (`brew outdated`)
/// 2. Sparkle appcast feeds (SUFeedURL in the app's Info.plist)
/// 3. Mac App Store (iTunes lookup API for receipt-bearing apps)
enum UpdateChecker {

    static func checkAll(apps: [InstalledApp]) async -> [AppUpdate] {
        var updates: [AppUpdate] = []
        updates += brewOutdated()
        await withTaskGroup(of: AppUpdate?.self) { group in
            for app in apps {
                group.addTask { await checkSparkleOrMAS(app) }
            }
            for await update in group {
                if let u = update { updates.append(u) }
            }
        }
        // De-duplicate by app name, preferring Homebrew (it can also install).
        var seen = Set<String>()
        return updates
            .sorted { a, b in a.channel == "Homebrew" && b.channel != "Homebrew" }
            .filter { seen.insert($0.appName.lowercased()).inserted }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    // MARK: Homebrew

    static func brewOutdated() -> [AppUpdate] {
        guard let brew = Shell.brewPath else { return [] }
        let out = Shell.run(brew, ["outdated", "--cask", "--greedy-latest", "--json=v2"], timeout: 180)
        guard out.succeeded, let data = out.stdout.data(using: .utf8) else { return [] }
        struct BrewJSON: Decodable {
            struct Cask: Decodable {
                let name: String
                let installed_versions: [String]?
                let current_version: String?
            }
            let casks: [Cask]
        }
        guard let parsed = try? JSONDecoder().decode(BrewJSON.self, from: data) else { return [] }
        return parsed.casks.compactMap { cask in
            let latest = cask.current_version ?? "?"
            let installed = cask.installed_versions?.first ?? "?"
            guard latest != installed, latest != "latest" else { return nil }
            return AppUpdate(id: "brew:" + cask.name,
                             appName: cask.name.replacingOccurrences(of: "-", with: " ").capitalized,
                             installedVersion: installed,
                             latestVersion: latest,
                             channel: "Homebrew",
                             howToUpdate: "brew upgrade --cask \(cask.name)")
        }
    }

    // MARK: Sparkle & App Store

    static func checkSparkleOrMAS(_ app: InstalledApp) async -> AppUpdate? {
        let bundle = Bundle(path: app.path)
        // Sparkle
        if let feed = bundle?.infoDictionary?["SUFeedURL"] as? String,
           let url = URL(string: feed) {
            if let latest = await latestSparkleVersion(url: url),
               isNewer(latest, than: app.version) {
                return AppUpdate(id: app.path, appName: app.name,
                                 installedVersion: app.version, latestVersion: latest,
                                 channel: "Sparkle",
                                 howToUpdate: "Open \(app.name) → Check for Updates")
            }
            return nil
        }
        // Mac App Store (receipt present)
        let receipt = app.path + "/Contents/_MASReceipt/receipt"
        if FileManager.default.fileExists(atPath: receipt) {
            if let latest = await masVersion(bundleID: app.bundleID),
               isNewer(latest, than: app.version) {
                return AppUpdate(id: app.path, appName: app.name,
                                 installedVersion: app.version, latestVersion: latest,
                                 channel: "App Store",
                                 howToUpdate: "Update via the App Store → Updates tab")
            }
        }
        return nil
    }

    static func latestSparkleVersion(url: URL) async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let parser = SparkleAppcastParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.bestVersion
    }

    static func masVersion(bundleID: String) async -> String? {
        var comps = URLComponents(string: "https://itunes.apple.com/lookup")!
        comps.queryItems = [URLQueryItem(name: "bundleId", value: bundleID)]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let version = results.first?["version"] as? String else { return nil }
        return version
    }

    /// Loose semantic version comparison.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let pa = parts(a), pb = parts(b)
        guard !pa.isEmpty, !pb.isEmpty else { return false }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

final class SparkleAppcastParser: NSObject, XMLParserDelegate {
    var bestVersion: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard elementName == "enclosure" else { return }
        let version = attributeDict["sparkle:shortVersionString"]
            ?? attributeDict["sparkle:version"]
        if let v = version {
            if let current = bestVersion {
                if UpdateChecker.isNewer(v, than: current) { bestVersion = v }
            } else {
                bestVersion = v
            }
        }
    }
}
