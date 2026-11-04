import Foundation

/// What curly knows about one curl flag.
public struct CurlOptionSpec: Equatable, Sendable {
    /// The long form including dashes, e.g. `--compressed`.
    public let long: String
    /// The short form including its dash, e.g. `-L`.
    public let short: String?
    /// Whether the flag is followed by an argument.
    public let takesValue: Bool
    /// One line of plain English, written for somebody who has not met HTTP.
    public let explanation: String

    public init(long: String, short: String? = nil, takesValue: Bool = false, explanation: String) {
        self.long = long
        self.short = short
        self.takesValue = takesValue
        self.explanation = explanation
    }

    /// The spelling curly prefers when it writes the flag out itself.
    public var canonicalFlag: String { long }
}

/// The flags curly recognises.
///
/// Recognition buys two things: the parser knows whether the next word is an
/// argument or the URL, and the editor can show a one-line explanation. A flag
/// that is missing from this table is not an error — it is kept exactly as it
/// was written and shown under "Other options".
public enum CurlOptionCatalog {
    /// Flags the parser pulls out into sections of their own rather than
    /// leaving in `CurlRequest.options`.
    public static let structural: Set<String> = [
        "--header", "-H",
        "--cookie", "-b",
        "--request", "-X",
        "--url",
        "--user", "-u",
        "--data", "-d",
        "--data-raw",
        "--data-binary",
        "--data-ascii",
        "--data-urlencode",
        "--form", "-F",
        "--form-string",
    ]

    public static let all: [CurlOptionSpec] = [
        .init(long: "--compressed", takesValue: false,
              explanation: "Asks the server to send the page zipped up, which makes it arrive faster. curl unzips it for you."),
        .init(long: "--location", short: "-L", takesValue: false,
              explanation: "If the server says \"that moved, look over there\", follow it to the new address instead of stopping."),
        .init(long: "--insecure", short: "-k", takesValue: false,
              explanation: "Carry on even if the site's security certificate does not check out. Handy for local testing, risky anywhere else."),
        .init(long: "--head", short: "-I", takesValue: false,
              explanation: "Ask only for the headers — the label on the parcel — and not the contents."),
        .init(long: "--get", short: "-G", takesValue: false,
              explanation: "Send the data as a query string on the end of the web address instead of in the body of the request."),
        .init(long: "--silent", short: "-s", takesValue: false,
              explanation: "Hide the progress meter and error messages."),
        .init(long: "--show-error", short: "-S", takesValue: false,
              explanation: "Still show errors even when things are otherwise quiet."),
        .init(long: "--verbose", short: "-v", takesValue: false,
              explanation: "Print the whole conversation with the server, which is a good way to see what is really sent."),
        .init(long: "--include", short: "-i", takesValue: false,
              explanation: "Print the response headers above the response body."),
        .init(long: "--fail", short: "-f", takesValue: false,
              explanation: "Treat an error page from the server as a failure instead of printing it."),
        .init(long: "--output", short: "-o", takesValue: true,
              explanation: "Write what comes back into a file with this name instead of printing it."),
        .init(long: "--remote-name", short: "-O", takesValue: false,
              explanation: "Save the response into a file named after the last part of the web address."),
        .init(long: "--user-agent", short: "-A", takesValue: true,
              explanation: "The name the request introduces itself with. Sites use it to tell browsers apart."),
        .init(long: "--referer", short: "-e", takesValue: true,
              explanation: "The page you were supposedly on when you followed a link here."),
        .init(long: "--max-time", short: "-m", takesValue: true,
              explanation: "Give up if the whole request takes longer than this many seconds."),
        .init(long: "--connect-timeout", takesValue: true,
              explanation: "Give up if it takes longer than this many seconds just to reach the server."),
        .init(long: "--retry", takesValue: true,
              explanation: "If the request fails, try it again up to this many times."),
        .init(long: "--proxy", short: "-x", takesValue: true,
              explanation: "Send the request through this middle-man server instead of straight to the site."),
        .init(long: "--cookie-jar", short: "-c", takesValue: true,
              explanation: "After the request, write any cookies the server handed back into this file."),
        .init(long: "--cert", short: "-E", takesValue: true,
              explanation: "Prove who you are with this client certificate file."),
        .init(long: "--key", takesValue: true,
              explanation: "The private key that goes with the client certificate."),
        .init(long: "--cacert", takesValue: true,
              explanation: "Check the site's certificate against this list of trusted authorities."),
        .init(long: "--resolve", takesValue: true,
              explanation: "Pretend a host name points at a particular address, without changing any settings."),
        .init(long: "--range", short: "-r", takesValue: true,
              explanation: "Ask for only part of the file, counted in bytes."),
        .init(long: "--limit-rate", takesValue: true,
              explanation: "Slow the transfer down to at most this speed."),
        .init(long: "--http1.1", takesValue: false,
              explanation: "Insist on the older HTTP/1.1 version of the protocol."),
        .init(long: "--http2", takesValue: false,
              explanation: "Ask to use HTTP/2, a faster version of the same protocol."),
        .init(long: "--http3", takesValue: false,
              explanation: "Ask to use HTTP/3, the newest version of the protocol."),
        .init(long: "--ipv4", short: "-4", takesValue: false,
              explanation: "Only use the older style of internet address."),
        .init(long: "--ipv6", short: "-6", takesValue: false,
              explanation: "Only use the newer style of internet address."),
        .init(long: "--globoff", short: "-g", takesValue: false,
              explanation: "Treat {} and [] in the web address as ordinary characters rather than a list to expand."),
        .init(long: "--path-as-is", takesValue: false,
              explanation: "Send the path exactly as written, without tidying up any . or .. in it."),
        .init(long: "--no-keepalive", takesValue: false,
              explanation: "Close the connection after this request instead of holding it open."),
        .init(long: "--interface", takesValue: true,
              explanation: "Send the request from this particular network connection on your machine."),
        .init(long: "--continue-at", short: "-C", takesValue: true,
              explanation: "Pick up a half-finished download from this point."),
        .init(long: "--upload-file", short: "-T", takesValue: true,
              explanation: "Send the contents of this file as the body of the request."),
        .init(long: "--trace", takesValue: true,
              explanation: "Write a very detailed log of the request into this file."),
        .init(long: "--write-out", short: "-w", takesValue: true,
              explanation: "After the request, print a little summary you describe here."),
        .init(long: "--oauth2-bearer", takesValue: true,
              explanation: "Send this token as proof of who you are."),
        .init(long: "--basic", takesValue: false,
              explanation: "Send the username and password the simple, standard way."),
        .init(long: "--digest", takesValue: false,
              explanation: "Send the username and password using a challenge-and-response scheme."),
        .init(long: "--negotiate", takesValue: false,
              explanation: "Work out the login scheme with the server rather than picking one up front."),
        .init(long: "--anyauth", takesValue: false,
              explanation: "Let curl choose whichever login scheme the server offers."),
        .init(long: "--next", takesValue: false,
              explanation: "Everything after this belongs to a second, separate request."),
        .init(long: "--parallel", short: "-Z", takesValue: false,
              explanation: "Run several transfers at the same time."),
        .init(long: "--tlsv1.2", takesValue: false,
              explanation: "Insist on at least this version of the encryption used to protect the connection."),
        .init(long: "--tlsv1.3", takesValue: false,
              explanation: "Insist on at least this version of the encryption used to protect the connection."),
        .init(long: "--proto", takesValue: true,
              explanation: "Restrict which kinds of address curl is willing to fetch."),
        .init(long: "--disable", short: "-q", takesValue: false,
              explanation: "Ignore your personal curl settings file for this run."),
    ]

    private static let byFlag: [String: CurlOptionSpec] = {
        var map: [String: CurlOptionSpec] = [:]
        for spec in all {
            map[spec.long] = spec
            if let short = spec.short { map[short] = spec }
        }
        // Structural flags are handled elsewhere but still need arity lookups.
        for spec in structuralSpecs {
            map[spec.long] = spec
            if let short = spec.short { map[short] = spec }
        }
        return map
    }()

    static let structuralSpecs: [CurlOptionSpec] = [
        .init(long: "--header", short: "-H", takesValue: true,
              explanation: "Adds one extra line of information to the request."),
        .init(long: "--cookie", short: "-b", takesValue: true,
              explanation: "Sends cookies with the request."),
        .init(long: "--request", short: "-X", takesValue: true,
              explanation: "Sets the method — the verb of the request."),
        .init(long: "--url", takesValue: true,
              explanation: "The web address to talk to."),
        .init(long: "--user", short: "-u", takesValue: true,
              explanation: "A username and password to log in with."),
        .init(long: "--data", short: "-d", takesValue: true, explanation: "Data to send in the body."),
        .init(long: "--data-raw", takesValue: true, explanation: "Data to send in the body, taken literally."),
        .init(long: "--data-binary", takesValue: true, explanation: "Data to send in the body, byte for byte."),
        .init(long: "--data-ascii", takesValue: true, explanation: "Data to send in the body, as text."),
        .init(long: "--data-urlencode", takesValue: true, explanation: "Data to send in the body, escaped for safety."),
        .init(long: "--form", short: "-F", takesValue: true, explanation: "One field of a form, which may be a file."),
        .init(long: "--form-string", takesValue: true, explanation: "One field of a form, always treated as plain text."),
    ]

    public static func spec(forFlag flag: String) -> CurlOptionSpec? { byFlag[flag] }

    /// Whether `flag` is followed by an argument. Unknown flags are assumed to
    /// stand alone, which is the only safe guess; an unknown flag written as
    /// `--thing=value` carries its value with it either way.
    public static func takesValue(_ flag: String) -> Bool {
        byFlag[flag]?.takesValue ?? false
    }

    public static func isStructural(_ flag: String) -> Bool { structural.contains(flag) }

    public static func explanation(forFlag flag: String) -> String? {
        byFlag[flag]?.explanation
    }
}
