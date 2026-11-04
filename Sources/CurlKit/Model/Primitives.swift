import Foundation

// MARK: - Identity

/// Rows in the editor need a stable identity for SwiftUI, but identity must not
/// take part in equality: the round-trip invariant `parse(generate(m)) == m`
/// compares two models that can never share identifiers. Every row type below
/// therefore carries an `id` and implements `==` over its content only.
public protocol RowIdentified: Identifiable, Equatable {
    var id: UUID { get }
}

// MARK: - Header

/// One `-H 'Name: value'` argument.
public struct Header: RowIdentified, Sendable {
    public let id: UUID
    public var name: String
    public var value: String
    /// Switched off headers stay in the editor but are left out of the command.
    public var isEnabled: Bool

    public init(name: String, value: String, isEnabled: Bool = true, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.value = value
        self.isEnabled = isEnabled
    }

    public static func == (lhs: Header, rhs: Header) -> Bool {
        lhs.name == rhs.name && lhs.value == rhs.value && lhs.isEnabled == rhs.isEnabled
    }

    /// `Name: value`, the form curl is handed.
    public var argument: String { "\(name): \(value)" }
}

// MARK: - Cookie

/// One `name=value` pair out of a cookie header or a `-b` argument.
public struct Cookie: RowIdentified, Sendable {
    public let id: UUID
    public var name: String
    public var value: String
    public var isEnabled: Bool

    public init(name: String, value: String, isEnabled: Bool = true, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.value = value
        self.isEnabled = isEnabled
    }

    public static func == (lhs: Cookie, rhs: Cookie) -> Bool {
        lhs.name == rhs.name && lhs.value == rhs.value && lhs.isEnabled == rhs.isEnabled
    }
}

/// Cookies travel either as a `Cookie:` header or as `-b`/`--cookie`. Either way
/// they get their own section in the editor, and the section remembers how it
/// was written so the command comes back out the way it went in.
public struct CookieSection: RowIdentified, Sendable {
    public enum Source: Equatable, Sendable {
        /// A `-H 'cookie: …'` argument; the associated value is the header name
        /// exactly as it was spelled (`cookie`, `Cookie`, …).
        case header(name: String)
        /// A `-b`/`--cookie` argument, spelled as it was written.
        case flag(name: String)
    }

    public let id: UUID
    public var source: Source
    public var cookies: [Cookie]
    public var isEnabled: Bool
    /// `-b` also accepts a file name, and a cookie header can hold something
    /// that is not a list of pairs. Anything we cannot split into rows is kept
    /// verbatim here and emitted unchanged.
    public var rawValue: String?

    public init(
        source: Source,
        cookies: [Cookie] = [],
        isEnabled: Bool = true,
        rawValue: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.source = source
        self.cookies = cookies
        self.isEnabled = isEnabled
        self.rawValue = rawValue
    }

    public static func == (lhs: CookieSection, rhs: CookieSection) -> Bool {
        lhs.source == rhs.source && lhs.cookies == rhs.cookies
            && lhs.isEnabled == rhs.isEnabled && lhs.rawValue == rhs.rawValue
    }

    /// The argument curl is handed, e.g. `a=1; b=2`.
    public var argumentValue: String {
        if let rawValue { return rawValue }
        return cookies.filter(\.isEnabled).map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

// MARK: - Query

/// One `name=value` pair out of the URL's query string. Both halves are stored
/// percent-encoded, exactly as they appear in the URL; the editor decodes them
/// for display and re-encodes on edit, so untouched pairs survive byte for byte.
public struct QueryItem: RowIdentified, Sendable {
    public let id: UUID
    public var name: String
    /// `nil` for a bare key with no `=` at all (`?debug`).
    public var value: String?
    public var isEnabled: Bool

    public init(name: String, value: String?, isEnabled: Bool = true, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.value = value
        self.isEnabled = isEnabled
    }

    public static func == (lhs: QueryItem, rhs: QueryItem) -> Bool {
        lhs.name == rhs.name && lhs.value == rhs.value && lhs.isEnabled == rhs.isEnabled
    }

    public var encoded: String {
        guard let value else { return name }
        return "\(name)=\(value)"
    }
}

// MARK: - Body

/// The flag a piece of body was written with. curl treats these differently, so
/// the distinction is kept rather than normalised away.
public enum BodyPartKind: String, CaseIterable, Sendable {
    case data
    case dataRaw
    case dataBinary
    case dataAscii
    case dataURLEncode
    case form
    case formString

    public var flag: String {
        switch self {
        case .data: return "--data"
        case .dataRaw: return "--data-raw"
        case .dataBinary: return "--data-binary"
        case .dataAscii: return "--data-ascii"
        case .dataURLEncode: return "--data-urlencode"
        case .form: return "--form"
        case .formString: return "--form-string"
        }
    }

    /// `-F` and `--form` build a multipart body; everything else is a plain one.
    public var isMultipart: Bool { self == .form || self == .formString }
}

/// One body-carrying argument.
public struct BodyPart: RowIdentified, Sendable {
    public let id: UUID
    public var kind: BodyPartKind
    public var value: String
    public var isEnabled: Bool

    public init(kind: BodyPartKind, value: String, isEnabled: Bool = true, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.value = value
        self.isEnabled = isEnabled
    }

    public static func == (lhs: BodyPart, rhs: BodyPart) -> Bool {
        lhs.kind == rhs.kind && lhs.value == rhs.value && lhs.isEnabled == rhs.isEnabled
    }
}

// MARK: - Credentials

/// A `-u user:password` argument.
public struct Credentials: Equatable, Sendable {
    public var user: String
    /// `nil` when the command said `-u user` and left curl to prompt.
    public var password: String?

    public init(user: String, password: String?) {
        self.user = user
        self.password = password
    }

    public var argument: String {
        guard let password else { return user }
        return "\(user):\(password)"
    }

    public init(argument: String) {
        if let separator = argument.firstIndex(of: ":") {
            user = String(argument[argument.startIndex..<separator])
            password = String(argument[argument.index(after: separator)...])
        } else {
            user = argument
            password = nil
        }
    }
}

// MARK: - Options

/// Any flag without a section of its own: `--compressed`, `-L`, `-k`, and also
/// anything curly does not recognise, which is kept verbatim rather than dropped.
public struct CurlOption: RowIdentified, Sendable {
    public let id: UUID
    /// The flag as written, including dashes (`--compressed`, `-L`).
    public var flag: String
    /// The flag's argument, when it takes one.
    public var value: String?
    public var isEnabled: Bool

    public init(flag: String, value: String? = nil, isEnabled: Bool = true, id: UUID = UUID()) {
        self.id = id
        self.flag = flag
        self.value = value
        self.isEnabled = isEnabled
    }

    public static func == (lhs: CurlOption, rhs: CurlOption) -> Bool {
        lhs.flag == rhs.flag && lhs.value == rhs.value && lhs.isEnabled == rhs.isEnabled
    }

    public var spec: CurlOptionSpec? { CurlOptionCatalog.spec(forFlag: flag) }

    /// True for a flag curly has never heard of; it still round-trips.
    public var isUnrecognised: Bool { spec == nil }
}
