import Foundation

/// Writes a `CurlRequest` back out as a curl command.
///
/// Rows that are switched off are left out, which is the whole point of the
/// toggles: flick one and watch the command change.
public enum CurlGenerator {
    public static func generate(_ request: CurlRequest, style: CurlStyle = .multiLine) -> String {
        script(request, style: style).text
    }

    public static func script(_ request: CurlRequest, style: CurlStyle = .multiLine) -> CurlScript {
        var builder = Builder(style: style)
        builder.build(request)
        return CurlScript(text: builder.text, segments: builder.segments)
    }

    // MARK: -

    private struct Builder {
        let style: CurlStyle
        var text = ""
        var offset = 0
        var segments: [CurlScript.Segment] = []

        init(style: CurlStyle) { self.style = style }

        // MARK: Low-level

        mutating func append(_ piece: String) {
            text += piece
            offset += piece.count
        }

        mutating func mark(_ ref: ElementRef, from start: Int) {
            segments.append(CurlScript.Segment(range: start..<offset, ref: ref))
        }

        /// The gap between two arguments: a space, or a continuation and an
        /// indent in the multi-line style.
        mutating func separator() {
            switch style {
            case .singleLine: append(" ")
            case .multiLine: append(" \\\n  ")
            }
        }

        /// Appends `flag value`, recording the whole thing under `ref`.
        /// Returns where the quoted value starts, when its insides can be
        /// mapped (which they can unless the value needed escaping).
        @discardableResult
        mutating func argument(flag: String?, value: String?, ref: ElementRef) -> Int? {
            separator()
            let start = offset
            if let flag { append(flag) }
            var innerStart: Int?
            if let value {
                if flag != nil { append(" ") }
                let quoted = ShellQuoting.quote(value)
                innerStart = ShellQuoting.isPlainlyWrapped(value, quoted: quoted)
                    ? offset + (quoted.hasPrefix("'") ? 1 : 0)
                    : nil
                append(quoted)
            }
            mark(ref, from: start)
            return innerStart
        }

        // MARK: The command

        mutating func build(_ request: CurlRequest) {
            let start = offset
            append("curl")
            mark(.command, from: start)

            appendURL(request)
            appendMethod(request)
            appendHeaders(request)
            appendCookies(request)
            appendCredentials(request)
            appendBody(request)
            appendOptions(request)
            appendExtras(request)
        }

        /// The address sits on the first line next to `curl`, the way every
        /// browser writes it.
        mutating func appendURL(_ request: CurlRequest) {
            var pieces: [(String, ElementRef?)] = []
            let url = request.url

            if !url.scheme.isEmpty {
                pieces.append((url.scheme, .urlScheme))
                pieces.append(("://", nil))
            }
            if let userInfo = url.userInfo, !userInfo.isEmpty {
                pieces.append((userInfo + "@", nil))
            }
            if !url.host.isEmpty { pieces.append((url.host, .urlHost)) }
            if let port = url.port, !port.isEmpty {
                pieces.append((":", nil))
                pieces.append((port, .urlPort))
            }
            if !url.path.isEmpty { pieces.append((url.path, .urlPath)) }

            let items = url.query.filter(\.isEnabled)
            if !items.isEmpty {
                pieces.append(("?", nil))
                for (position, item) in items.enumerated() {
                    if position > 0 { pieces.append(("&", nil)) }
                    pieces.append((item.encoded, .queryItem(item.id)))
                }
            }
            if let fragment = url.fragment { pieces.append(("#" + fragment, nil)) }

            let plain = pieces.map(\.0).joined()
            guard !plain.isEmpty else { return }

            append(" ")
            let start = offset
            if url.usesURLFlag { append("--url ") }

            let quoted = ShellQuoting.quote(plain)
            let mapsCleanly = ShellQuoting.isPlainlyWrapped(plain, quoted: quoted)
            let innerStart = offset + (quoted.hasPrefix("'") ? 1 : 0)
            append(quoted)
            mark(.url, from: start)

            guard mapsCleanly else { return }
            var cursor = innerStart
            var queryLower: Int?
            var queryUpper: Int?
            for piece in pieces {
                let end = cursor + piece.0.count
                if let ref = piece.1 {
                    segments.append(CurlScript.Segment(range: cursor..<end, ref: ref))
                    if case .queryItem = ref {
                        queryLower = queryLower ?? cursor
                        queryUpper = end
                    }
                }
                cursor = end
            }
            if let queryLower, let queryUpper {
                segments.append(CurlScript.Segment(range: queryLower..<queryUpper, ref: .urlQuery))
            }
        }

        mutating func appendMethod(_ request: CurlRequest) {
            guard let method = request.explicitMethod else { return }
            argument(flag: "-X", value: method, ref: .method)
        }

        mutating func appendHeaders(_ request: CurlRequest) {
            for header in request.headers where header.isEnabled {
                argument(flag: "-H", value: header.argument, ref: .header(header.id))
                if header.name.caseInsensitiveCompare("Authorization") == .orderedSame,
                   let last = segments.last {
                    segments.append(CurlScript.Segment(range: last.range, ref: .auth))
                }
            }
        }

        mutating func appendCookies(_ request: CurlRequest) {
            for section in request.cookieSections where section.isEnabled {
                let cookies = section.cookies.filter(\.isEnabled)
                if section.rawValue == nil && cookies.isEmpty { continue }

                var pieces: [(String, ElementRef?)] = []
                let flag: String
                switch section.source {
                case .header(let name):
                    flag = "-H"
                    pieces.append((name + ": ", nil))
                case .flag(let name):
                    flag = name
                }

                if let raw = section.rawValue {
                    pieces.append((raw, nil))
                } else {
                    for (position, cookie) in cookies.enumerated() {
                        if position > 0 { pieces.append(("; ", nil)) }
                        pieces.append(("\(cookie.name)=\(cookie.value)", .cookie(cookie.id)))
                    }
                }

                let plain = pieces.map(\.0).joined()
                let innerStart = argument(flag: flag, value: plain, ref: .cookieSection(section.id))
                guard let innerStart else { continue }
                var cursor = innerStart
                for (piece, ref) in pieces {
                    let end = cursor + piece.count
                    if let ref { segments.append(CurlScript.Segment(range: cursor..<end, ref: ref)) }
                    cursor = end
                }
            }
        }

        mutating func appendCredentials(_ request: CurlRequest) {
            guard let credentials = request.credentials else { return }
            argument(flag: "-u", value: credentials.argument, ref: .auth)
        }

        mutating func appendBody(_ request: CurlRequest) {
            for part in request.bodyParts where part.isEnabled {
                argument(flag: part.kind.flag, value: part.value, ref: .bodyPart(part.id))
                if let last = segments.last {
                    segments.append(CurlScript.Segment(range: last.range, ref: .body))
                }
            }
        }

        mutating func appendOptions(_ request: CurlRequest) {
            for option in request.options where option.isEnabled {
                argument(flag: option.flag, value: option.value, ref: .option(option.id))
            }
        }

        mutating func appendExtras(_ request: CurlRequest) {
            for (index, extra) in request.extraArguments.enumerated() {
                argument(flag: nil, value: extra, ref: .extraArgument(index))
            }
        }
    }
}
