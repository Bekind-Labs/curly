import Foundation

/// Works out what curl would actually put on the wire for a `CurlRequest`.
///
/// Nothing here opens a socket. Keeping the translation separate from the
/// sending means the fiddly parts — which flags change the body, what the
/// implied `Content-Type` is, where cookies end up — are testable on any
/// platform, and the app is left with a thin `URLSession` call.
public enum RequestPlanner {

    /// Flags that change nothing about the request curly builds, because
    /// `URLSession` already behaves that way or they only affect curl's own
    /// console output. They are not reported as unsupported.
    private static let harmless: Set<String> = [
        "--compressed",   // URLSession asks for and unwraps compression itself
        "--silent", "--show-error", "--verbose", "--include",
        "--fail", "--globoff", "--disable", "--no-keepalive",
        "--http1.1", "--http2", "--http3",
        "--ipv4", "--ipv6",
        "--basic", "--anyauth",
        "--tlsv1.2", "--tlsv1.3",
        "--path-as-is",
    ]

    /// Flags curly reads and acts on itself.
    private static let handled: Set<String> = [
        "--location", "--insecure", "--head", "--get",
        "--max-time", "--connect-timeout",
        "--user-agent", "--referer",
    ]

    public static func plan(for request: CurlRequest) throws -> RequestPlan {
        var warnings: [RequestPlanWarning] = []
        var url = request.url
        if url.scheme.isEmpty { url.scheme = "http" }   // curl's own default
        guard !url.host.isEmpty else { throw RequestPlanError.noAddress }

        // MARK: Body

        let parts = request.bodyParts.filter(\.isEnabled)
        var body: Data?
        var impliedContentType: String?

        if parts.contains(where: \.kind.isMultipart) {
            let boundary = "curlyFormBoundary\(UUID().uuidString)"
            body = try multipartBody(parts, boundary: boundary)
            impliedContentType = "multipart/form-data; boundary=\(boundary)"
            if parts.contains(where: { !$0.kind.isMultipart }) {
                warnings.append(.mixedMultipart)
            }
        } else if !parts.isEmpty {
            let joined = try parts.map(try encodedValue(of:)).joined(separator: "&")
            if request.isOptionEnabled("--get") {
                // -G moves the data onto the end of the address instead.
                url.query.append(contentsOf: URLParts.parseQuery(joined))
            } else {
                body = Data(joined.utf8)
                impliedContentType = "application/x-www-form-urlencoded"
            }
        }

        // MARK: Headers

        var headers: [HeaderField] = request.headers
            .filter(\.isEnabled)
            .map { HeaderField(name: $0.name, value: $0.value) }

        let cookies = request.cookieSections
            .filter(\.isEnabled)
            .compactMap { section -> String? in
                if let raw = section.rawValue {
                    warnings.append(.unreadableCookieFile(raw))
                    return nil
                }
                let value = section.argumentValue
                return value.isEmpty ? nil : value
            }
        if !cookies.isEmpty {
            headers.append(HeaderField(name: "Cookie", value: cookies.joined(separator: "; ")))
        }

        if let credentials = request.credentials {
            let encoded = Data(credentials.argument.utf8).base64EncodedString()
            headers.append(HeaderField(name: "Authorization", value: "Basic \(encoded)"))
        }

        if let userAgent = request.option("--user-agent")?.value,
           request.isOptionEnabled("--user-agent") {
            headers.append(HeaderField(name: "User-Agent", value: userAgent))
        }
        if let referer = request.option("--referer")?.value,
           request.isOptionEnabled("--referer") {
            headers.append(HeaderField(name: "Referer", value: referer))
        }

        // curl adds a Content-Type for you when you send a body and have not
        // said what it is.
        if let impliedContentType,
           !headers.contains(where: { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
            headers.append(HeaderField(name: "Content-Type", value: impliedContentType))
        }

        // MARK: Options

        var timeout: TimeInterval?
        if let maxTime = request.option("--max-time")?.value, let seconds = TimeInterval(maxTime) {
            timeout = seconds
        } else if let connect = request.option("--connect-timeout")?.value,
                  let seconds = TimeInterval(connect) {
            timeout = seconds
        }

        let unsupported = request.options
            .filter(\.isEnabled)
            .map(\.flag)
            .map { flag in CurlOptionCatalog.spec(forFlag: flag)?.long ?? flag }
            .filter { !harmless.contains($0) && !handled.contains($0) }

        if !request.extraArguments.isEmpty {
            warnings.append(.extraAddresses)
        }

        return RequestPlan(
            method: request.method,
            url: url.text,
            headers: headers,
            body: body,
            followsRedirects: request.isOptionEnabled("--location"),
            skipsCertificateChecks: request.isOptionEnabled("--insecure"),
            timeout: timeout,
            verbosity: request.verbosity,
            unsupportedOptions: Array(Set(unsupported)).sorted(),
            warnings: warnings
        )
    }

    // MARK: - Bodies

    /// `@file` means "read this file" for every data flag except `--data-raw`,
    /// which is the flag browsers use precisely because it takes `@` literally.
    private static func encodedValue(of part: BodyPart) throws -> String {
        switch part.kind {
        case .dataURLEncode:
            return urlEncodedPiece(part.value)
        case .dataRaw:
            return part.value
        default:
            guard part.value.hasPrefix("@") else { return part.value }
            let path = String(part.value.dropFirst())
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
                throw RequestPlanError.unreadableFile(path)
            }
            // -d and friends strip line breaks out of a file; --data-binary does not.
            return part.kind == .dataBinary
                ? contents
                : contents.replacingOccurrences(of: "\r", with: "")
                    .replacingOccurrences(of: "\n", with: "")
        }
    }

    /// curl's `--data-urlencode` forms: `content`, `=content`, `name=content`,
    /// `@file` and `name@file`.
    private static func urlEncodedPiece(_ value: String) -> String {
        if let equals = value.firstIndex(of: "=") {
            let name = String(value[value.startIndex..<equals])
            let content = String(value[value.index(after: equals)...])
            let encoded = URLParts.encode(content)
            return name.isEmpty ? encoded : "\(name)=\(encoded)"
        }
        return URLParts.encode(value)
    }

    private static func multipartBody(_ parts: [BodyPart], boundary: String) throws -> Data {
        var body = Data()
        for part in parts where part.kind.isMultipart {
            let (name, rawValue) = splitField(part.value)
            body.append(Data("--\(boundary)\r\n".utf8))

            // A leading @ means a file, unless the flag was --form-string.
            if part.kind == .form, rawValue.hasPrefix("@") {
                let path = String(rawValue.dropFirst()).components(separatedBy: ";").first ?? ""
                guard let contents = FileManager.default.contents(atPath: path) else {
                    throw RequestPlanError.unreadableFile(path)
                }
                let filename = (path as NSString).lastPathComponent
                body.append(Data(
                    "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8
                ))
                body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
                body.append(contents)
            } else {
                body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
                body.append(Data(rawValue.utf8))
            }
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    private static func splitField(_ value: String) -> (String, String) {
        guard let equals = value.firstIndex(of: "=") else { return (value, "") }
        return (
            String(value[value.startIndex..<equals]),
            String(value[value.index(after: equals)...])
        )
    }
}

// MARK: - Verbosity on the model

extension CurlRequest {
    /// How much of the exchange the command asks to see, read from `-s`, `-i`
    /// and `-v`. Setting it rewrites those flags, so the generated command and
    /// the response pane never disagree.
    public var verbosity: Verbosity {
        get {
            if isOptionEnabled("--verbose") { return .verbose }
            if isOptionEnabled("--include") { return .headers }
            if isOptionEnabled("--silent") { return .quiet }
            return .normal
        }
        set {
            for flag in Verbosity.allFlags {
                setOption(flag, enabled: false)
            }
            if let flag = newValue.flag {
                setOption(flag, enabled: true)
            }
        }
    }
}
