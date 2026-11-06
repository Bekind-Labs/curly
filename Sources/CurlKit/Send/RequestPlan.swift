import Foundation

/// One header as it will actually go over the wire.
public struct HeaderField: Equatable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// How much of the exchange to show, mirroring curl's own output flags.
public enum Verbosity: String, CaseIterable, Sendable {
    /// `-s`: just the body, and keep quiet about everything else.
    case quiet
    /// The default: just the body.
    case normal
    /// `-i`: the response headers above the body.
    case headers
    /// `-v`: the whole conversation, request included.
    case verbose

    /// The flag that turns this on, if any.
    public var flag: String? {
        switch self {
        case .quiet: return "--silent"
        case .normal: return nil
        case .headers: return "--include"
        case .verbose: return "--verbose"
        }
    }

    /// Every flag in this family, so switching between them can clear the rest.
    public static var allFlags: [String] {
        allCases.compactMap(\.flag)
    }

    public var showsResponseHeaders: Bool {
        self == .headers || self == .verbose
    }

    public var showsRequest: Bool { self == .verbose }
}

/// Everything needed to actually perform the request, worked out from a
/// `CurlRequest` without touching the network.
///
/// This is deliberately a plain value: the translation from flags to a real
/// request is the fiddly part and it is all testable here, while the app layer
/// is left with a few lines of `URLSession`.
public struct RequestPlan: Equatable, Sendable {
    public var method: String
    public var url: String
    public var headers: [HeaderField]
    public var body: Data?
    /// curl only follows redirects when told to with `-L`.
    public var followsRedirects: Bool
    /// `-k`. The app warns loudly when this is on.
    public var skipsCertificateChecks: Bool
    /// `--max-time`, or `--connect-timeout` when that is all there is.
    public var timeout: TimeInterval?
    public var verbosity: Verbosity
    /// Flags curly recognises but cannot act on when it sends the request
    /// itself. Shown to the user rather than ignored quietly.
    public var unsupportedOptions: [String]
    /// Anything else worth saying before pressing send.
    public var warnings: [String]

    public init(
        method: String,
        url: String,
        headers: [HeaderField] = [],
        body: Data? = nil,
        followsRedirects: Bool = false,
        skipsCertificateChecks: Bool = false,
        timeout: TimeInterval? = nil,
        verbosity: Verbosity = .normal,
        unsupportedOptions: [String] = [],
        warnings: [String] = []
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.followsRedirects = followsRedirects
        self.skipsCertificateChecks = skipsCertificateChecks
        self.timeout = timeout
        self.verbosity = verbosity
        self.unsupportedOptions = unsupportedOptions
        self.warnings = warnings
    }

    /// The `> GET /things HTTP/1.1` style transcript of what was sent, which is
    /// what `-v` shows.
    public var requestTranscript: [String] {
        var lines: [String] = []
        let target = URLParts(text: url)
        let path = target.path.isEmpty ? "/" : target.path
        let query = target.query.filter(\.isEnabled).map(\.encoded).joined(separator: "&")
        lines.append("> \(method) \(path)\(query.isEmpty ? "" : "?" + query) HTTP/1.1")
        lines.append("> Host: \(target.host)\(target.port.map { ":" + $0 } ?? "")")
        for header in headers {
            lines.append("> \(header.name): \(header.value)")
        }
        if let body, !body.isEmpty {
            lines.append(">")
            lines.append("> [\(body.count) bytes of body]")
        }
        return lines
    }
}

public enum RequestPlanError: Error, Equatable, CustomStringConvertible {
    case noAddress
    case unreadableFile(String)

    public var description: String {
        switch self {
        case .noAddress:
            return "There is no web address to send this to."
        case .unreadableFile(let path):
            return "curly could not read the file “\(path)”."
        }
    }
}
