import Foundation

/// A curl command, taken apart.
///
/// This is a plain value type: every edit in the UI is an assignment, and the
/// command shown on the right is `CurlGenerator.generate(request)` of whatever
/// the value happens to be. Nothing here knows about SwiftUI, and nothing here
/// sends anything anywhere.
///
/// The model stays close to what was actually written — flags keep their
/// spelling, query values keep their escaping — and the friendlier views
/// (cookies, auth, form fields, JSON) are projections on top, in
/// `CurlRequest+Semantics.swift`.
public struct CurlRequest: Equatable, Sendable {
    public var url: URLParts
    /// The value of `-X`, when one was written. `nil` means curl is left to
    /// pick the method itself, which is what browsers emit for a plain GET.
    public var explicitMethod: String?
    public var headers: [Header]
    public var cookieSections: [CookieSection]
    /// `-u user:password`.
    public var credentials: Credentials?
    public var bodyParts: [BodyPart]
    /// Flags without a section of their own, including unrecognised ones.
    public var options: [CurlOption]
    /// Bare words that were neither a flag nor the first address — extra URLs,
    /// mostly. Kept so nothing is ever silently dropped.
    public var extraArguments: [String]

    public init(
        url: URLParts = URLParts(),
        explicitMethod: String? = nil,
        headers: [Header] = [],
        cookieSections: [CookieSection] = [],
        credentials: Credentials? = nil,
        bodyParts: [BodyPart] = [],
        options: [CurlOption] = [],
        extraArguments: [String] = []
    ) {
        self.url = url
        self.explicitMethod = explicitMethod
        self.headers = headers
        self.cookieSections = cookieSections
        self.credentials = credentials
        self.bodyParts = bodyParts
        self.options = options
        self.extraArguments = extraArguments
    }

    // MARK: Method

    public static let commonMethods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    /// The method curl would use if `-X` were taken away: POST when there is a
    /// body, HEAD for `-I`, PUT for `-T`, GET otherwise.
    public var impliedMethod: String {
        if isOptionEnabled("--head") { return "HEAD" }
        if isOptionEnabled("--get") { return "GET" }
        if bodyParts.contains(where: \.isEnabled) { return "POST" }
        if isOptionEnabled("--upload-file") { return "PUT" }
        return "GET"
    }

    /// The method that will actually be sent. Setting it writes `-X` unless the
    /// method is the one curl would have chosen anyway, in which case the flag
    /// is dropped — less noise in the command for the same request.
    public var method: String {
        get { explicitMethod ?? impliedMethod }
        set { explicitMethod = (newValue == impliedMethod) ? nil : newValue }
    }

    // MARK: Options

    public func option(_ flag: String) -> CurlOption? {
        let spec = CurlOptionCatalog.spec(forFlag: flag)
        return options.first { candidate in
            if candidate.flag == flag { return true }
            guard let spec, let candidateSpec = candidate.spec else { return false }
            return candidateSpec == spec
        }
    }

    public func isOptionEnabled(_ flag: String) -> Bool {
        option(flag)?.isEnabled ?? false
    }

    /// Adds or removes a value-less flag such as `--compressed`.
    public mutating func setOption(_ flag: String, enabled: Bool) {
        let spec = CurlOptionCatalog.spec(forFlag: flag)
        let existing = options.firstIndex { candidate in
            candidate.flag == flag || (spec != nil && candidate.spec == spec)
        }
        if let index = existing {
            if enabled {
                options[index].isEnabled = true
            } else {
                options.remove(at: index)
            }
        } else if enabled {
            options.append(CurlOption(flag: flag))
        }
    }

    // MARK: Headers

    /// Case-insensitive, because header names are.
    public func header(named name: String) -> Header? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func headerIndex(named name: String) -> Int? {
        headers.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Sets a header's value, adding or removing the row as needed. Keeps the
    /// existing spelling of the name so `content-type` does not become
    /// `Content-Type` behind the user's back.
    public mutating func setHeader(_ name: String, to value: String?) {
        if let index = headerIndex(named: name) {
            if let value {
                headers[index].value = value
            } else {
                headers.remove(at: index)
            }
        } else if let value {
            headers.append(Header(name: name, value: value))
        }
    }

    // MARK: Convenience

    public var isEmpty: Bool {
        self == CurlRequest(url: URLParts(scheme: "", host: ""))
            || (url.host.isEmpty && headers.isEmpty && bodyParts.isEmpty && options.isEmpty)
    }

    /// The same request with every switched-off row removed. Generating a
    /// command throws away disabled rows, so this is what a command generated
    /// from this request parses back into.
    public func enabledOnly() -> CurlRequest {
        var copy = self
        copy.url.query = url.query.filter(\.isEnabled)
        copy.headers = headers.filter(\.isEnabled)
        copy.cookieSections = cookieSections
            .filter(\.isEnabled)
            .map { section in
                var section = section
                section.cookies = section.cookies.filter(\.isEnabled)
                return section
            }
            .filter { $0.rawValue != nil || !$0.cookies.isEmpty }
        copy.bodyParts = bodyParts.filter(\.isEnabled)
        copy.options = options.filter(\.isEnabled)
        return copy
    }
}
