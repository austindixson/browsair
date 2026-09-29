import Foundation
import WebKit

/// A single declarative content-blocker rule.
///
/// `loadType` is the important one: without `["third-party"]` a rule blocks the domain for
/// *first-party* requests too — which is how a blanket `*google-analytics.com` could take down a
/// Google sign-in document. Keeping the trigger typed (rather than a loose dictionary) makes that
/// mistake impossible to express.
struct ContentBlockerRule: Encodable, Equatable {
    struct Trigger: Encodable, Equatable {
        let urlFilter: String
        let ifDomain: [String]?
        let unlessDomain: [String]?
        let loadType: [String]?

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
            case loadType = "load-type"
        }
    }
    struct Action: Encodable, Equatable { let type: String }

    let trigger: Trigger
    let action: Action
}

final class PrivacyPolicy: @unchecked Sendable {
    static let shared = PrivacyPolicy()

    /// UserDefaults key holding the user's per-site tracker allowlist.
    static let allowlistDefaultsKey = "browsair.privacy.allowedSites"

    static let blockedHosts = [
        "google-analytics.com", "googletagmanager.com", "doubleclick.net",
        "googlesyndication.com", "facebook.net",
        "adsystem.com", "adservice.google.com", "adnxs.com",
        "scorecardresearch.com", "hotjar.com", "mixpanel.com",
        "segment.io", "amplitude.com", "crazyegg.com", "clicktale.net",
        "quantserve.com", "chartbeat.com", "quantcount.com", "mc.yandex.ru",
    ]

    /// Hosts that get a declarative third-party block rule. Kept separate from
    /// `blockedHosts` so the two rule kinds (host rules vs path-endpoint rules) cannot be
    /// confused by a trailing-slash parser.
    static let blockedRuleHosts: [String] = blockedHosts.map { host in
        host.hasSuffix("/") ? String(host.dropLast()) : host
    }

    /// Beacon endpoints that live on an otherwise legitimate domain. `facebook.com/tr` is the
    /// share/beacon endpoint: blocking the whole of `facebook.com` would break first-party
    /// sign-in, and a content-blocker rule keyed on `url-filter` has no path component in the
    /// app's WebKit version, so this is enforced in `shouldBlock` (the navigation-delegate path)
    /// and intentionally left out of the declarative rules.
    static let blockedEndpoints: [(host: String, pathPrefix: String)] = [
        ("facebook.com", "/tr"),
    ]

    /// Hosts that legitimately serve first-party sign-in documents; never blanket-blocked.
    static let protectedLoginHosts: Set<String> = [
        "google.com", "accounts.google.com", "googleusercontent.com", "gstatic.com",
        "microsoftonline.com", "login.microsoftonline.com", "microsoft.com", "live.com",
        "github.com", "githubusercontent.com", "appleid.apple.com", "id.apple.com",
        "fastmail.com", "protonmail.com", "proton.me", "outlook.com", "office.com",
    ]

    /// Last error from building/compiling the rule set. Nil in the fresh default state.
    private(set) var lastBuildError: String?

    /// Whether third-party tracking protection is active. Blocking stays on by default; the
    /// per-site `allowedSites` set exempts only those sites. This is kept as a property so a
    /// future global master switch has a single place to live.
    private(set) var blocksThirdPartyTrackers = true
    /// The site the user allowlisted (stored host, lowercased).
    private(set) var lastAllowedSite: String?
    /// The sites the user allowed to load trackers. Loaded from `defaults` at init and written
    /// back on every change, so "Allow trackers on this site" survives relaunch.
    private(set) var allowedSites: Set<String> = []

    /// `nil` for an isolated instance that never reads or writes persisted state. The app-wide
    /// `shared` singleton passes `.standard`, which is what makes the allowlist survive relaunch.
    private let defaults: UserDefaults?

    /// Lock protecting `allowedSites`/`lastAllowedSite`. `PrivacyPolicy` is reached from the
    /// main actor (the "Allow…" button) and from WebKit's navigation-delegate callbacks, which
    /// run off-main on a background queue, so the set is read and written concurrently.
    private let lock = NSLock()

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let defaults, let stored = defaults.array(forKey: Self.allowlistDefaultsKey) as? [String] {
            allowedSites = Set(stored.map { $0.lowercased() })
            lastAllowedSite = allowedSites.max()
        }
    }

    func noteBuildError(_ message: String?) {
        lastBuildError = message
    }

    /// Whether tracking is allowed for a host. A host is covered when it *is* an allowlisted
    /// host or sits beneath it (`www.news.site.com` under `news.site.com`). Sibling hosts such
    /// as `other.site.com` are NOT covered — matching the stored host directly (instead of
    /// collapsing to a registrable domain) avoids needing a public-suffix list.
    func isTrackingAllowed(forHost host: String) -> Bool {
        let host = host.lowercased()
        lock.lock()
        let sites = allowedSites
        lock.unlock()
        return sites.contains { allowed in
            host == allowed || host.hasSuffix("." + allowed)
        }
    }

    /// Allow tracking on a site. Only that host (and hosts beneath it) skip blocking; blocking
    /// stays on everywhere else, including sibling hosts under the same parent domain.
    func allowTracking(forSite site: String) {
        let host = site.lowercased()
        lock.lock()
        allowedSites.insert(host)
        lastAllowedSite = host
        let snapshot = allowedSites
        lock.unlock()
        persist(snapshot)
    }

    /// Remove a site from the allowlist.
    func revokeTracking(forSite site: String) {
        let host = site.lowercased()
        lock.lock()
        allowedSites.remove(host)
        lastAllowedSite = allowedSites.max()
        let snapshot = allowedSites
        lock.unlock()
        persist(snapshot)
    }

    private func persist(_ sites: Set<String>) {
        defaults?.set(sites.sorted(), forKey: Self.allowlistDefaultsKey)
    }

    func shouldBlock(url: URL, firstPartyHost: String? = nil) -> Bool {
        guard blocksThirdPartyTrackers else { return false }
        // Per-site allowlist: trackers load freely when the page we're on is allowlisted.
        if let firstPartyHost, isTrackingAllowed(forHost: firstPartyHost) { return false }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return false }
        if Self.isProtected(host) { return false }
        // Beacon endpoints on otherwise-legitimate domains, checked before the first-party
        // exemption: `facebook.com/tr` embedded from a facebook.com page is still a beacon.
        if Self.isBlockedEndpoint(url, host: host) { return true }
        if let firstPartyHost, isSameOrSubdomain(host, of: firstPartyHost.lowercased()) { return false }
        // Host-level tracker matches (exact or subdomain of a blocked host).
        if Self.blockedRuleHosts.contains(where: { matchesBlockDomain(host, pattern: $0) }) { return true }
        // Legacy heuristic prefixes, kept from the original ruleset.
        return host.hasPrefix("ads.") || host.hasPrefix("ad.")
            || host.hasPrefix("pixel.") || host.hasPrefix("analytics.")
    }

    /// A tracker domain blocks both itself and anything beneath it (`www.google-analytics.com`
    /// must match the `google-analytics.com` entry). `isSameOrSubdomain` alone checks the wrong
    /// direction for the bare `www.` subdomain, so we match exactly or as a subdomain suffix.
    private func matchesBlockDomain(_ host: String, pattern: String) -> Bool {
        host == pattern || host.hasSuffix("." + pattern)
    }

    /// Whether a URL targets a beacon endpoint hosted on an otherwise-legitimate domain.
    static func isBlockedEndpoint(_ url: URL, host: String) -> Bool {
        Self.blockedEndpoints.contains { endpoint in
            isSameOrSubdomainStatic(host, of: endpoint.host)
                && url.path.hasPrefix(endpoint.pathPrefix)
        }
    }

    static func isProtected(_ host: String) -> Bool {
        for protected in protectedLoginHosts where isSameOrSubdomainStatic(host, of: protected) {
            return true
        }
        return false
    }

    /// Match the resource URL's host, including subdomains and an optional port.
    static func hostFilterRegex(for host: String) -> String? {
        let lowered = host.lowercased()
        let labels = lowered.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.allSatisfy({ label in
            !label.isEmpty && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }) else { return nil }
        let escaped = lowered.replacingOccurrences(of: ".", with: "\\.")
        return "^https?://([a-z0-9-]+\\.)*\(escaped)(:[0-9]+)?/"
    }

    /// Whether a host would receive its own third-party block rule (excludes login hosts and
    /// hosts whose filter can't be compiled safely).
    func isBlockedAsRule(host: String) -> Bool {
        guard !Self.isProtected(host) else { return false }
        return Self.blockedHosts.contains { isSameOrSubdomain(host, of: $0) }
            && Self.hostFilterRegex(for: host) != nil
    }

    /// Third-party resource rules; page-domain conditions must not select tracker hosts.
    var contentBlockerJSON: String {
        var skipped: [String] = []
        var rules: [ContentBlockerRule] = []
        for host in Self.blockedHosts where !host.contains("/") && !Self.isProtected(host) {
            guard let filter = Self.hostFilterRegex(for: host) else {
                skipped.append(host)
                continue
            }
            rules.append(ContentBlockerRule(
                trigger: .init(urlFilter: filter,
                               ifDomain: nil, unlessDomain: nil, loadType: ["third-party"]),
                action: .init(type: "block")))
        }
        if !skipped.isEmpty {
            noteBuildError("content-blocker: skipped hosts with unsafe filter chars: \(skipped.joined(separator: ", "))")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(rules) else {
            noteBuildError("failed to encode content-blocker rules")
            return "[]"
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func isSameOrSubdomainStatic(_ host: String, of domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private func isSameOrSubdomain(_ host: String, of domain: String) -> Bool {
        Self.isSameOrSubdomainStatic(host, of: domain)
    }
}
