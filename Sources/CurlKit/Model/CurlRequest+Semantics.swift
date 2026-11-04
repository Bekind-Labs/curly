import Foundation

// Friendlier views onto the model. Each one reads the flags that are actually
// there and writes back into those same flags, so the Headers section never
// starts lying about what is sent.

// MARK: - Cookies

extension CurlRequest {
    /// Every cookie in the request, from wherever it was written.
    public var allCookies: [Cookie] {
        cookieSections.flatMap(\.cookies)
    }

    /// Where a newly typed cookie should go: an existing section if there is
    /// one, otherwise a fresh `Cookie:` header.
    public mutating func addCookie(name: String = "", value: String = "") {
        if let index = cookieSections.firstIndex(where: { $0.rawValue == nil }) {
            cookieSections[index].cookies.append(Cookie(name: name, value: value))
        } else {
            cookieSections.append(
                CookieSection(source: .header(name: "Cookie"), cookies: [Cookie(name: name, value: value)])
            )
        }
    }

    /// Splits `a=1; b=2` into rows. Returns `nil` if the text is not a list of
    /// pairs at all, which is how a `-b cookies.txt` file name is recognised.
    public static func parseCookieList(_ text: String) -> [Cookie]? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        var cookies: [Cookie] = []
        for piece in trimmed.components(separatedBy: ";") {
            let pair = piece.trimmingCharacters(in: .whitespaces)
            if pair.isEmpty { continue }
            guard let equals = pair.firstIndex(of: "=") else { return nil }
            cookies.append(
                Cookie(
                    name: String(pair[pair.startIndex..<equals]),
                    value: String(pair[pair.index(after: equals)...])
                )
            )
        }
        return cookies
    }
}

// MARK: - Auth

/// How the request proves who you are, read back out of the flags.
public enum AuthKind: Equatable, Sendable {
    case none
    /// `-u user:password`.
    case basicFlag(Credentials)
    /// `Authorization: Basic …`, which is the same thing spelled out by hand.
    case basicHeader(Credentials)
    /// `Authorization: Bearer <token>`.
    case bearer(String)
    /// An `Authorization` header curly does not recognise; shown as-is.
    case otherHeader(scheme: String, value: String)
}

extension CurlRequest {
    public var authorizationHeader: Header? { header(named: "Authorization") }

    public var auth: AuthKind {
        if let credentials { return .basicFlag(credentials) }
        guard let header = authorizationHeader else { return .none }
        let parts = header.value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let scheme = parts.first else { return .none }
        let rest = parts.count > 1 ? String(parts[1]) : ""
        switch scheme.lowercased() {
        case "basic":
            guard
                let data = Data(base64Encoded: rest),
                let decoded = String(data: data, encoding: .utf8)
            else {
                return .otherHeader(scheme: String(scheme), value: rest)
            }
            return .basicHeader(Credentials(argument: decoded))
        case "bearer":
            return .bearer(rest)
        default:
            return .otherHeader(scheme: String(scheme), value: rest)
        }
    }

    /// Rewrites whichever flag the credentials came from.
    public mutating func setBasicCredentials(_ newValue: Credentials) {
        switch auth {
        case .basicHeader:
            let encoded = Data(newValue.argument.utf8).base64EncodedString()
            setHeader("Authorization", to: "Basic \(encoded)")
        default:
            credentials = newValue
        }
    }

    public mutating func setBearerToken(_ token: String) {
        setHeader("Authorization", to: "Bearer \(token)")
    }

    public mutating func clearAuth() {
        credentials = nil
        setHeader("Authorization", to: nil)
    }
}

// MARK: - Body

/// What the body looks like once you squint at it.
public enum BodyShape: Equatable, Sendable {
    /// No body at all.
    case empty
    /// A single blob of text, which may or may not be JSON.
    case text
    /// `a=1&b=2`, the shape an ordinary HTML form posts.
    case formURLEncoded
    /// `-F` fields, which can carry files.
    case multipart
    /// `--data-urlencode` pieces, usually alongside `-G`.
    case urlEncodedFields
    /// A mixture curly will not try to be clever about.
    case mixed
}

extension CurlRequest {
    public var enabledBodyParts: [BodyPart] { bodyParts.filter(\.isEnabled) }

    /// The value of the `Content-Type` header, if there is one.
    public var contentType: String? {
        header(named: "Content-Type")?.value
    }

    public var contentTypeBase: String? {
        contentType?.split(separator: ";").first.map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
    }

    public mutating func setContentType(_ value: String?) {
        setHeader("Content-Type", to: value)
    }

    public var bodyShape: BodyShape {
        let parts = enabledBodyParts
        if parts.isEmpty { return .empty }
        if parts.allSatisfy(\.kind.isMultipart) { return .multipart }
        if parts.allSatisfy({ $0.kind == .dataURLEncode }) { return .urlEncodedFields }
        let dataKinds: Set<BodyPartKind> = [.data, .dataRaw, .dataBinary, .dataAscii]
        guard parts.allSatisfy({ dataKinds.contains($0.kind) }) else { return .mixed }
        if parts.count == 1, contentTypeBase == "application/x-www-form-urlencoded" {
            return .formURLEncoded
        }
        return .text
    }

    /// The body as one piece of text, which is how curl joins `-d` arguments.
    public var bodyText: String {
        enabledBodyParts
            .filter { !$0.kind.isMultipart }
            .map(\.value)
            .joined(separator: "&")
    }

    /// Replaces the body with a single blob of text, keeping the flag spelling
    /// that was already in use so a Chrome command stays a `--data-raw` one.
    public mutating func setBodyText(_ text: String) {
        let kind = bodyParts.first(where: { !$0.kind.isMultipart })?.kind ?? .dataRaw
        let existingID = bodyParts.first(where: { !$0.kind.isMultipart })?.id
        let replacement = BodyPart(kind: kind, value: text, id: existingID ?? UUID())
        bodyParts = text.isEmpty ? [] : [replacement]
    }

    /// True when the body parses as JSON.
    public var bodyIsJSON: Bool {
        JSONFormatter.isValid(bodyText)
    }

    /// Form fields read out of an `a=1&b=2` body.
    public var formFields: [FormField] {
        FormField.parse(bodyText)
    }

    public mutating func setFormFields(_ fields: [FormField]) {
        setBodyText(FormField.join(fields))
    }
}

/// One row of a form-encoded body.
public struct FormField: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var value: String

    public init(name: String, value: String, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.value = value
    }

    public static func == (lhs: FormField, rhs: FormField) -> Bool {
        lhs.name == rhs.name && lhs.value == rhs.value
    }

    /// Splits `a=1&b=2`, showing the values with their `%20`s turned back into
    /// spaces.
    public static func parse(_ body: String) -> [FormField] {
        guard !body.isEmpty else { return [] }
        return body.split(separator: "&", omittingEmptySubsequences: false).map { pair in
            if let equals = pair.firstIndex(of: "=") {
                return FormField(
                    name: URLParts.decode(String(pair[pair.startIndex..<equals])),
                    value: URLParts.decode(String(pair[pair.index(after: equals)...]))
                )
            }
            return FormField(name: URLParts.decode(String(pair)), value: "")
        }
    }

    public static func join(_ fields: [FormField]) -> String {
        fields
            .map { "\(URLParts.encode($0.name))=\(URLParts.encode($0.value))" }
            .joined(separator: "&")
    }
}
