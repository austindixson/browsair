import Foundation

/// Outcome of classifying an address-bar or search-box entry.
enum URLQueryKind: Equatable {
    /// Load the (fully-qualified) `value` as a URL in the page surface.
    case navigate
    /// Open `value` with the external handler (mailto:, tel:, etc.).
    case external
    /// `value` is a search-engine results URL built from the query.
    case search
    /// Nothing usable was entered.
    case empty
}

struct URLQueryResult: Equatable {
    let scheme: URLQueryKind
    let value: String

    var url: URL? {
        switch scheme {
        case .navigate, .search, .external: return URL(string: value)
        case .empty: return nil
        }
    }

    static let externalSchemes: Set<String> = ["mailto", "tel", "sms", "callto", "x-apple-data-detectors"]

    /// Classify a raw address-bar entry.
    /// - Parameters:
    ///   - raw: exactly what the user typed.
    ///   - current: the current page URL, used to resolve relative paths, queries and fragments.
    ///   - searchBase: the search engine endpoint (`q=` is appended).
    static func classify(
        _ raw: String,
        current: String? = nil,
        searchBase: String = "https://duckduckgo.com/"
    ) -> URLQueryResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return URLQueryResult(scheme: .empty, value: "") }

        // 1. Absolute URL with a recognized scheme, or a non-web scheme to hand off.
        if let scheme = recognizedScheme(of: trimmed) {
            if externalSchemes.contains(scheme) {
                return URLQueryResult(scheme: .external, value: trimmed)
            }
            return URLQueryResult(scheme: .navigate, value: trimmed)
        }

        // 2. In-page fragment.
        if trimmed.hasPrefix("#") {
            return resolve(current: current, suffix: trimmed)
        }
        // 3. Absolute path or query relative to the current page.
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("?") {
            return resolve(current: current, suffix: trimmed)
        }

        let lower = trimmed.lowercased()
        let hostPart = stripPath(from: lower)          // drop path/query/fragment for host checks
        let hostOnly = stripPort(from: hostPart)       // drop :port for host checks

        // 4. loopback / Bonjour service → plain HTTP (never a bare ".local").
        if hostOnly == "localhost" || hostOnly.hasSuffix(".localhost")
            || (hostOnly.hasSuffix(".local") && hostOnly != ".local") {
            return URLQueryResult(scheme: .navigate, value: "http://\(trimmed)")
        }

        // 5. Bracketed IPv6 literal.
        if hostOnly.hasPrefix("[") {
            return URLQueryResult(scheme: .navigate, value: "http://\(trimmed)")
        }

        // 6. IPv4 literal (validated octets) → plain HTTP; malformed octets → search.
        if looksLikeIPv4(hostOnly) {
            return validIPv4(hostOnly)
                ? URLQueryResult(scheme: .navigate, value: "http://\(trimmed)")
                : search(trimmed, base: searchBase)
        }

        // 7. Whitespace (with no scheme) → search.
        if trimmed.rangeOfCharacter(from: .whitespaces) != nil {
            return search(trimmed, base: searchBase)
        }

        // 8. Hostname candidate: dotted, alphabetic TLD of length ≥ 2, and a valid (or absent) port.
        let labels = hostOnly.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let lastLabel = labels.last ?? ""
        let portValue = port(of: hostPart)
        let tldIsAlpha = lastLabel.count >= 2 && lastLabel.allSatisfy { $0.isLetter }
        let portIsValid = portValue.map { (1...65_535).contains($0) } ?? true
        let hasDot = hostOnly.contains(".") && !hostOnly.hasPrefix(".")
        if hasDot, tldIsAlpha, portIsValid {
            return URLQueryResult(scheme: .navigate, value: "https://\(trimmed)")
        }

        // 9. Anything else → search.
        return search(trimmed, base: searchBase)
    }

    // MARK: - Helpers

    private static func search(_ query: String, base: String) -> URLQueryResult {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let separator = base.contains("?") ? "&" : "?"
        return URLQueryResult(scheme: .search, value: "\(base)\(separator)q=\(encoded)")
    }

    private static func resolve(current: String?, suffix: String) -> URLQueryResult {
        if let base = current, let baseURL = URL(string: base),
           let resolved = URL(string: suffix, relativeTo: baseURL)?.absoluteURL {
            return URLQueryResult(scheme: .navigate, value: resolved.absoluteString)
        }
        // No current page to anchor to → treat the trailing text as a search.
        let query = String(suffix.dropFirst())
        return search(query.isEmpty ? suffix : query, base: "https://duckduckgo.com/")
    }

    /// Returns the scheme if the entry starts with `<scheme>:` and the scheme is a web or
    /// known-external scheme. A colon-only label like `example.com:8443` is NOT a scheme.
    private static func recognizedScheme(of value: String) -> String? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let scheme = String(value[value.startIndex..<colon]).lowercased()
        guard !scheme.isEmpty else { return nil }
        // Schemes never contain '/', '?' or '#'; the label before ':' must be valid chars.
        guard scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-" }),
              scheme.first!.isLetter else { return nil }
        let web: Set<String> = ["http", "https", "about", "file", "blob", "data", "javascript", "view-source"]
        return (web.contains(scheme) || externalSchemes.contains(scheme)) ? scheme : nil
    }

    private static func stripPath(from value: String) -> String {
        for marker in ["/", "?", "#"] {
            if let idx = value.range(of: marker)?.lowerBound { return String(value[value.startIndex..<idx]) }
        }
        return value
    }

    private static func stripPort(from hostPart: String) -> String {
        if hostPart.hasPrefix("[") { return hostPart }
        guard let colon = hostPart.lastIndex(of: ":") else { return hostPart }
        return String(hostPart[hostPart.startIndex..<colon])
    }

    private static func port(of hostPart: String) -> Int? {
        if hostPart.hasPrefix("[") { return nil }
        guard let colon = hostPart.lastIndex(of: ":") else { return nil }
        let digits = hostPart[hostPart.index(after: colon)...]
        return Int(digits)
    }

    private static func looksLikeIPv4(_ value: String) -> Bool {
        value.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
    }

    private static func validIPv4(_ value: String) -> Bool {
        value.split(separator: ".").allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }
}
