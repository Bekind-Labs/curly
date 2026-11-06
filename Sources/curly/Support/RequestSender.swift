import CurlKit
import Foundation

/// What came back. Kept as data plus a little bookkeeping; how much of it gets
/// shown is up to the verbosity setting.
struct SentResponse: Equatable {
    var statusCode: Int
    var statusText: String
    var httpVersion: String
    var headers: [HeaderField]
    var body: Data
    var duration: TimeInterval
    /// Where the request ended up, which differs from where it started when
    /// redirects were followed.
    var finalURL: String?
    /// The request as it went out, for the verbose transcript.
    var requestTranscript: [String]
    var warnings: [String]
    /// Flags curl would act on that curly cannot when it sends the request
    /// itself. Shown rather than silently ignored.
    var unsupportedOptions: [String]

    var isSuccess: Bool { (200..<300).contains(statusCode) }
    var isRedirect: Bool { (300..<400).contains(statusCode) }
    var isError: Bool { statusCode >= 400 }

    /// `< HTTP/1.1 200 OK` and the response headers, the way `-v` shows them.
    var responseTranscript: [String] {
        var lines = ["< \(httpVersion) \(statusCode) \(statusText)"]
        for header in headers {
            lines.append("< \(header.name): \(header.value)")
        }
        return lines
    }

    /// The body as text, laid out nicely when it is JSON.
    var prettyBody: String {
        guard !body.isEmpty else { return "" }
        guard let text = String(data: body, encoding: .utf8) else {
            return "[\(body.count) bytes that are not text]"
        }
        return JSONFormatter.prettyPrinted(text) ?? text
    }

    var contentType: String? {
        headers.first { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
    }
}

/// Performs the request a `RequestPlan` describes.
///
/// This is the only part of curly that touches the network, and it exists only
/// because the user pressed Send.
enum RequestSender {
    static func send(_ plan: RequestPlan) async throws -> SentResponse {
        guard let url = URL(string: plan.url) else {
            throw SendError.badAddress(plan.url)
        }

        var request = URLRequest(url: url)
        request.httpMethod = plan.method
        request.httpBody = plan.body
        for header in plan.headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        if let timeout = plan.timeout {
            request.timeoutInterval = timeout
        }
        // curl does not reuse anything from a previous run, and a cached answer
        // would be a confusing thing to show next to a command you just edited.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        let delegate = SendDelegate(
            followsRedirects: plan.followsRedirects,
            skipsCertificateChecks: plan.skipsCertificateChecks
        )
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let started = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw SendError.transport(error)
        }
        let duration = Date().timeIntervalSince(started)

        guard let http = response as? HTTPURLResponse else {
            throw SendError.notHTTP
        }

        let headers: [HeaderField] = http.allHeaderFields
            .compactMap { key, value in
                guard let name = key as? String else { return nil }
                return HeaderField(name: name, value: String(describing: value))
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }

        return SentResponse(
            statusCode: http.statusCode,
            statusText: HTTPURLResponse.localizedString(forStatusCode: http.statusCode).capitalizedFirst,
            httpVersion: "HTTP/1.1",
            headers: headers,
            body: data,
            duration: duration,
            finalURL: http.url?.absoluteString,
            requestTranscript: plan.requestTranscript,
            warnings: plan.warnings,
            unsupportedOptions: plan.unsupportedOptions
        )
    }
}

enum SendError: Error, CustomStringConvertible {
    case badAddress(String)
    case notHTTP
    case transport(URLError)

    var description: String {
        switch self {
        case .badAddress(let url):
            return String(format: L("send.error.address", "“%@” is not an address curly can send to."), url)
        case .notHTTP:
            return L("send.error.notHTTP", "That address did not answer with HTTP.")
        case .transport(let error):
            switch error.code {
            case .notConnectedToInternet:
                return L("send.error.offline", "This machine does not seem to be online.")
            case .cannotFindHost:
                return L("send.error.host", "That host name could not be looked up. Is it spelled right?")
            case .cannotConnectToHost:
                return L("send.error.connect", "Nothing answered at that address and port.")
            case .timedOut:
                return L("send.error.timeout", "The server took too long to answer.")
            case .secureConnectionFailed, .serverCertificateUntrusted,
                 .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot:
                return L(
                    "send.error.tls",
                    "The site's security certificate could not be trusted. Adding -k tells curl to carry on anyway, which is fine for a local server and risky anywhere else."
                )
            case .cancelled:
                return L("send.error.cancelled", "Cancelled.")
            default:
                return error.localizedDescription
            }
        }
    }
}

/// Handles the two curl flags that cannot be expressed on a `URLRequest`.
private final class SendDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let followsRedirects: Bool
    let skipsCertificateChecks: Bool

    init(followsRedirects: Bool, skipsCertificateChecks: Bool) {
        self.followsRedirects = followsRedirects
        self.skipsCertificateChecks = skipsCertificateChecks
    }

    /// URLSession follows redirects by default and curl does not, so without
    /// this a command with no -L would quietly behave differently here than in
    /// the terminal.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(followsRedirects ? request : nil)
    }

    /// Only when the command says -k, which the response pane says out loud.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            skipsCertificateChecks,
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
