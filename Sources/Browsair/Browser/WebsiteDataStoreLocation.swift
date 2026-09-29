import Foundation

/// Where WebKit keeps its persistent website data for a given bundle identifier.
///
/// WebKit keys persistent storage on the *bundle identifier* that `Bundle.main` reports at
/// launch, not on any path the app chooses:
///
///   - cookies:            `~/Library/HTTPStorages/<bundle-id>.binarycookies`
///   - LocalStorage/IndexedDB: `~/Library/WebKit/<bundle-id>/WebsiteData`
///
/// A `swift build`/`swift run` binary is a bare Mach-O, not an app bundle, so `Bundle.main`
/// reports no identifier (measured: `nil`). In that state WebKit has no stable identity to key
/// storage on, which is the real reason login cookies did not survive relaunch (audit F3). The
/// app must therefore run from a `.app` bundle with a CFBundleIdentifier before persistent data
/// is meaningful.
enum WebsiteDataStoreLocation {
    /// The value of the `BROWSAIR_BUNDLE_ID` environment override, if set and non-empty.
    ///
    /// A testing seam: it lets a caller assert path resolution for a specific bundle id without a
    /// real `Bundle`. Production does not set it; two-process cookie survival is validated by
    /// `scripts/cookie-persistence-check.sh`, not by this override.
    static let bundleIDOverrideEnvironmentKey = "BROWSAIR_BUNDLE_ID"

    /// The bundle identifier WebKit will actually key persistent storage on, for the given bundle
    /// and environment. Deterministic and testable: no shared global state, no `@MainActor`.
    ///
    /// Resolution order: explicit `BROWSAIR_BUNDLE_ID` override (test seam), else
    /// `bundle.bundleIdentifier`. Returns `nil` when neither is present — the bare-binary case.
    static func resolvedBundleIdentifier(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let override = environment[bundleIDOverrideEnvironmentKey]?.trimmingCharacters(in: .whitespaces),
           !override.isEmpty {
            return override
        }
        return bundle.bundleIdentifier
    }

    /// Whether persistent website data can be trusted to survive a relaunch, given the resolved
    /// bundle identifier. `nil` means the process has no LaunchServices-registered identity, so
    /// WebKit storage is effectively per-process and cookies will be lost on quit.
    static func hasPersistentIdentity(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return !bundleID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The system location WebKit uses for LocalStorage/IndexedDB for a bundle id.
    /// Only meaningful when `bundleID` is the identifier WebKit resolved for this process.
    static func webKitWebsiteDataURL(
        bundleID: String,
        fileManager: FileManager = .default
    ) -> URL {
        homeDirectory(fileManager: fileManager)
            .appendingPathComponent("Library/WebKit", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("WebsiteData", isDirectory: true)
    }

    /// The system location WebKit uses for cookies for a bundle id.
    static func cookieStorageURL(
        bundleID: String,
        fileManager: FileManager = .default
    ) -> URL {
        homeDirectory(fileManager: fileManager)
            .appendingPathComponent("Library/HTTPStorages", isDirectory: true)
            .appendingPathComponent("\(bundleID).binarycookies")
    }

    private static func homeDirectory(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
    }
}
