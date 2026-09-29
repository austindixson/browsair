import Foundation
import WebKit

/// Maps low-level WebKit/URLSession errors to actionable strings and builds the persistent
/// website-data location. Previously provisional failures and a crashed WebContent process were
/// surfaced as (or replaced by) an empty string, so the user saw a blank page with no reason.
enum PageSurfaceError {
    static func pageMessage(forProvisionalError error: Error) -> String {
        let ns = error as NSError
        let host = (ns.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)
            ?? (ns.userInfo[NSURLErrorFailingURLPeerTrustErrorKey] != nil ? "the server" : "")
        let hostName = host.isEmpty ? host : (URL(string: host)?.host ?? host)

        switch ns.code {
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
            return "Can't reach \(hostName.isEmpty ? "this site" : hostName) — check the address or your connection."
        case NSURLErrorTimedOut:
            return "\(hostName.isEmpty ? "The site" : hostName) took too long to respond."
        case NSURLErrorNotConnectedToInternet:
            return "You're not connected to the internet."
        case NSURLErrorSecureConnectionFailed, NSURLErrorBadServerResponse:
            return "A secure connection to \(hostName.isEmpty ? "this site" : hostName) couldn't be established (certificate or server error)."
        case NSURLErrorUnsupportedURL, NSURLErrorBadURL:
            return "This address can't be opened in Browsair."
        case NSURLErrorCancelled:
            return "" // user-initiated cancel; don't show a scary error
        default:
            return ns.localizedDescription
        }
    }

    static let contentProcessTerminatedMessage =
        "The page stopped responding and was reloaded."
}

/// Owns the on-disk location for WebKit's persistent website data (cookies, localStorage,
/// IndexedDB). The actual keys WebKit uses are derived from `WebsiteDataStoreLocation`, which
/// resolves the bundle identifier the store is keyed on — see that type for why a bare binary
/// has no persistent identity.
enum WebsiteDataStoreSupport {
    /// The system location WebKit uses for this process's persistent website data.
    ///
    /// Returns `nil` when the process has no bundle identifier (a `swift run` binary), in which
    /// case there is no persistent location to speak of and login cookies will not survive quit.
    @MainActor
    static func persistentStoreURL(fileManager: FileManager = .default) -> URL? {
        guard let bundleID = WebsiteDataStoreLocation.resolvedBundleIdentifier(environment: ProcessInfo.processInfo.environment) else {
            return nil
        }
        let dir = WebsiteDataStoreLocation.webKitWebsiteDataURL(bundleID: bundleID, fileManager: fileManager)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The persistent (disk-backed) store. `WKWebsiteDataStore.default()` is the process-wide
    /// non-ephemeral store, so cookies and website data survive relaunches. Passing it explicitly
    /// documents the intent that previously relied on an unconfigured implicit default.
    @MainActor
    static func makePersistentStore() -> WKWebsiteDataStore {
        .default()
    }

    /// Remove all website data (cookies, storage) for a "Clear browsing data" action.
    @MainActor
    static func clearAllData(completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
            completion()
        }
    }
}

