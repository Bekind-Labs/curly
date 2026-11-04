import Foundation

public enum CurlParserError: Error, Equatable, CustomStringConvertible {
    case empty
    case notACurlCommand(firstWord: String)
    case tokenizer(ShellTokenizerError)
    case missingValue(flag: String)

    public var description: String {
        switch self {
        case .empty:
            return "There is nothing to import."
        case .notACurlCommand(let firstWord):
            return "This starts with “\(firstWord)”, so it does not look like a curl command."
        case .tokenizer(let error):
            return error.description
        case .missingValue(let flag):
            return "The flag \(flag) needs something after it."
        }
    }
}

/// Turns a curl command line into a `CurlRequest`.
///
/// It is deliberately forgiving: a flag curly has never heard of is kept
/// verbatim rather than rejected, and so is anything else it cannot classify.
/// The one hard rule is that the command has to start with `curl`.
public enum CurlParser {
    /// A cheap check for "does the clipboard hold a curl command?".
    public static func looksLikeCurl(_ text: String) -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 200_000 else { return false }
        if trimmed.hasPrefix("$ ") { trimmed = String(trimmed.dropFirst(2)) }
        guard let firstWord = trimmed.split(whereSeparator: \.isWhitespace).first else { return false }
        return isCurlWord(String(firstWord)) && trimmed.count > 5
    }

    private static func isCurlWord(_ word: String) -> Bool {
        let name = word.split(separator: "/").last.map(String.init) ?? word
        return name == "curl" || name == "curl.exe"
    }

    public static func parse(_ command: String) throws -> CurlRequest {
        let tokens: [ShellToken]
        do {
            tokens = try ShellTokenizer.tokenize(command)
        } catch let error as ShellTokenizerError {
            throw CurlParserError.tokenizer(error)
        }

        var words = tokens.map(\.text)
        // Shell prompts people copy along with the command.
        while let first = words.first, first == "$" || first == "%" || first == ">" {
            words.removeFirst()
        }
        guard let first = words.first else { throw CurlParserError.empty }
        guard isCurlWord(first) else { throw CurlParserError.notACurlCommand(firstWord: first) }

        var parser = Worker(words: Array(words.dropFirst()))
        return try parser.run()
    }

    // MARK: -

    private struct Worker {
        let words: [String]
        var index = 0
        var request = CurlRequest(url: URLParts(scheme: "", host: ""))
        var hasURL = false
        var afterDoubleDash = false

        init(words: [String]) { self.words = words }

        mutating func run() throws -> CurlRequest {
            while index < words.count {
                let word = words[index]
                index += 1

                if afterDoubleDash {
                    takePositional(word)
                } else if word == "--" {
                    afterDoubleDash = true
                } else if word.hasPrefix("--"), word.count > 2 {
                    try handleLongFlag(word)
                } else if word.hasPrefix("-"), word.count > 1 {
                    try handleShortFlags(word)
                } else {
                    takePositional(word)
                }
            }
            return request
        }

        mutating func nextWord(for flag: String) throws -> String {
            guard index < words.count else { throw CurlParserError.missingValue(flag: flag) }
            let word = words[index]
            index += 1
            return word
        }

        mutating func handleLongFlag(_ word: String) throws {
            var flag = word
            var value: String?
            if let equals = word.firstIndex(of: "=") {
                flag = String(word[word.startIndex..<equals])
                value = String(word[word.index(after: equals)...])
            }
            if value == nil, CurlOptionCatalog.takesValue(flag) {
                value = try nextWord(for: flag)
            }
            apply(flag: flag, value: value)
        }

        /// `-sSL` is three flags; `-H'Accept: */*'` is one flag with its value
        /// stuck to it. curl allows both, and browsers emit the second.
        mutating func handleShortFlags(_ word: String) throws {
            let letters = Array(word.dropFirst())
            var position = 0
            while position < letters.count {
                let flag = "-" + String(letters[position])
                position += 1
                if CurlOptionCatalog.takesValue(flag) {
                    let value: String
                    if position < letters.count {
                        value = String(letters[position...])
                        position = letters.count
                    } else {
                        value = try nextWord(for: flag)
                    }
                    apply(flag: flag, value: value)
                } else {
                    apply(flag: flag, value: nil)
                }
            }
        }

        mutating func takePositional(_ word: String) {
            if hasURL {
                request.extraArguments.append(word)
            } else {
                request.url = URLParts(text: word)
                hasURL = true
            }
        }

        mutating func apply(flag: String, value: String?) {
            switch flag {
            case "-H", "--header":
                addHeader(value ?? "")
            case "-b", "--cookie":
                addCookieFlag(spelling: flag, value: value ?? "")
            case "-X", "--request":
                request.explicitMethod = value
            case "--url":
                request.url = URLParts(text: value ?? "", usesURLFlag: true)
                hasURL = true
            case "-u", "--user":
                request.credentials = Credentials(argument: value ?? "")
            case "-d", "--data":
                addBody(.data, value)
            case "--data-raw":
                addBody(.dataRaw, value)
            case "--data-binary":
                addBody(.dataBinary, value)
            case "--data-ascii":
                addBody(.dataAscii, value)
            case "--data-urlencode":
                addBody(.dataURLEncode, value)
            case "-F", "--form":
                addBody(.form, value)
            case "--form-string":
                addBody(.formString, value)
            default:
                request.options.append(CurlOption(flag: flag, value: value))
            }
        }

        mutating func addBody(_ kind: BodyPartKind, _ value: String?) {
            request.bodyParts.append(BodyPart(kind: kind, value: value ?? ""))
        }

        /// A `Cookie:` header is pulled out into the cookie section, because
        /// that is where a beginner will look for it.
        mutating func addHeader(_ argument: String) {
            let name: String
            let value: String
            if let colon = argument.firstIndex(of: ":") {
                name = String(argument[argument.startIndex..<colon])
                value = String(argument[argument.index(after: colon)...])
                    .drop(while: { $0 == " " })
                    .description
            } else {
                name = argument
                value = ""
            }

            if name.caseInsensitiveCompare("cookie") == .orderedSame {
                if let cookies = CurlRequest.parseCookieList(value) {
                    request.cookieSections.append(
                        CookieSection(source: .header(name: name), cookies: cookies)
                    )
                } else {
                    request.cookieSections.append(
                        CookieSection(source: .header(name: name), rawValue: value)
                    )
                }
                return
            }

            request.headers.append(Header(name: name, value: value))
        }

        mutating func addCookieFlag(spelling: String, value: String) {
            if let cookies = CurlRequest.parseCookieList(value), !cookies.isEmpty {
                request.cookieSections.append(
                    CookieSection(source: .flag(name: spelling), cookies: cookies)
                )
            } else {
                request.cookieSections.append(
                    CookieSection(source: .flag(name: spelling), rawValue: value)
                )
            }
        }
    }
}
