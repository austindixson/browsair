import Foundation

struct PrivacyPolicy: Sendable {
    static let shared = PrivacyPolicy()

    private let blockedHosts = [
        "google-analytics.com", "googletagmanager.com", "doubleclick.net",
        "googlesyndication.com", "facebook.net", "facebook.com/tr",
        "adsystem.com", "adservice.google.com", "adnxs.com",
        "scorecardresearch.com", "hotjar.com", "mixpanel.com",
        "segment.io", "amplitude.com", "pixel.wp.com"
    ]

    func shouldBlock(url: URL, firstPartyHost: String? = nil) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return false }
        if let firstPartyHost, isSameOrSubdomain(host, of: firstPartyHost.lowercased()) { return false }
        return blockedHosts.contains { pattern in
            pattern.contains("/") ? host == pattern.split(separator: "/").first.map(String.init) : isSameOrSubdomain(host, of: pattern)
        } || host.hasPrefix("ads.") || host.hasPrefix("ad.") || host.hasPrefix("pixel.") || host.hasPrefix("analytics.")
    }

    var contentBlockerJSON: String {
        let rules = blockedHosts.filter { !$0.contains("/") }.map { host in
            ["trigger": ["url-filter": ".*", "if-domain": ["*\(host)"]], "action": ["type": "block"]]
        }
        return String(data: (try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }

    private func isSameOrSubdomain(_ host: String, of domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}
