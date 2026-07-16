import Foundation

/// Support links — Marmot is free forever; these are the tip jar.
/// Buttons appear in the UI only for links that are filled in.
enum Support {

    /// Always available: the repo itself (stars are support too!).
    static let repoURL = URL(string: "https://github.com/EPeiffer94/Marmot")!

    /// Fill in after enrolling at https://github.com/sponsors — the in-app
    /// button shows up automatically once this is non-nil.
    static let sponsorsURL: URL? = URL(string: "https://github.com/sponsors/EPeiffer94")

    /// Ko-fi tip jar.
    static let coffeeURL: URL? = URL(string: "https://ko-fi.com/kasakir")
}
