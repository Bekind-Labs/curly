import Foundation

/// A web address broken into the pieces the editor shows as separate fields.
///
/// Parsing is done by hand rather than with `URL`/`URLComponents` so that odd
/// but legal addresses survive unchanged; nothing here re-encodes anything.
public struct URLParts: Equatable, Sendable {
    /// `https`, or empty when the address was written without one.
    public var scheme: String
    /// Anything before an `@` in the address, e.g. `user:password`.
    public var userInfo: String?
    public var host: String
    /// Written as text so `:0080` is not quietly turned into `:80`.
    public var port: String?
    /// Everything from the first `/`, e.g. `/v1/widgets`. May be empty.
    public var path: String
    public var query: [QueryItem]
    /// Everything after a `#`. Browsers never send it, but it round-trips.
    public var fragment: String?
    /// True when the address was written as `--url 'https://…'` rather than as
    /// a bare argument.
    public var usesURLFlag: Bool

    public init(
        scheme: String = "https",
        userInfo: String? = nil,
        host: String = "",
        port: String? = nil,
        path: String = "",
        query: [QueryItem] = [],
        fragment: String? = nil,
        usesURLFlag: Bool = false
    ) {
        self.scheme = scheme
        self.userInfo = userInfo
        self.host = host
        self.port = port
        self.path = path
        self.query = query
        self.fragment = fragment
        self.usesURLFlag = usesURLFlag
    }

    // MARK: Text form

    /// The whole address as one string. Setting it re-splits into the fields,
    /// which is how the editor keeps the raw box and the part boxes in step.
    public var text: String {
        get {
            var result = ""
            if !scheme.isEmpty { result += scheme + "://" }
            if let userInfo { result += userInfo + "@" }
            result += host
            if let port, !port.isEmpty { result += ":" + port }
            result += path
            let pairs = query.filter(\.isEnabled).map(\.encoded)
            if !pairs.isEmpty { result += "?" + pairs.joined(separator: "&") }
            if let fragment { result += "#" + fragment }
            return result
        }
        set {
            let parsed = URLParts(text: newValue, usesURLFlag: usesURLFlag)
            scheme = parsed.scheme
            userInfo = parsed.userInfo
            host = parsed.host
            port = parsed.port
            path = parsed.path
            query = parsed.query
            fragment = parsed.fragment
        }
    }

    /// The address without its query string, which is what the editor shows
    /// when the query is being edited row by row.
    public var textWithoutQuery: String {
        var copy = self
        copy.query = []
        copy.fragment = nil
        return copy.text
    }

    public init(text: String, usesURLFlag: Bool = false) {
        self.init(scheme: "", usesURLFlag: usesURLFlag)

        var rest = Substring(text)

        if let schemeRange = rest.range(of: "://") {
            scheme = String(rest[rest.startIndex..<schemeRange.lowerBound])
            rest = rest[schemeRange.upperBound...]
        }

        // Fragment first: it can contain ? and / that are not query or path.
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...])
            rest = rest[rest.startIndex..<hash]
        }

        if let questionMark = rest.firstIndex(of: "?") {
            let queryText = rest[rest.index(after: questionMark)...]
            query = URLParts.parseQuery(String(queryText))
            rest = rest[rest.startIndex..<questionMark]
        }

        // Authority runs to the first slash.
        var authority = rest
        if let slash = rest.firstIndex(of: "/") {
            authority = rest[rest.startIndex..<slash]
            path = String(rest[slash...])
        } else {
            path = ""
        }

        if let at = authority.lastIndex(of: "@") {
            userInfo = String(authority[authority.startIndex..<at])
            authority = authority[authority.index(after: at)...]
        }

        if authority.hasPrefix("[") {
            // IPv6 literal: [::1]:8080
            if let closing = authority.firstIndex(of: "]") {
                host = String(authority[authority.startIndex...closing])
                let after = authority[authority.index(after: closing)...]
                if after.hasPrefix(":") { port = String(after.dropFirst()) }
            } else {
                host = String(authority)
            }
        } else if let colon = authority.lastIndex(of: ":") {
            host = String(authority[authority.startIndex..<colon])
            port = String(authority[authority.index(after: colon)...])
        } else {
            host = String(authority)
        }
    }

    public static func parseQuery(_ text: String) -> [QueryItem] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "&", omittingEmptySubsequences: false).map { pair in
            if let equals = pair.firstIndex(of: "=") {
                return QueryItem(
                    name: String(pair[pair.startIndex..<equals]),
                    value: String(pair[pair.index(after: equals)...])
                )
            }
            return QueryItem(name: String(pair), value: nil)
        }
    }

    // MARK: Percent encoding helpers for the editor

    /// What a query value says once the `%20`s are turned back into spaces.
    public static func decode(_ encoded: String) -> String {
        encoded.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? encoded
    }

    /// Escapes a query name or value so it is safe to put in a web address.
    public static func encode(_ plain: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return plain.addingPercentEncoding(withAllowedCharacters: allowed) ?? plain
    }
}
