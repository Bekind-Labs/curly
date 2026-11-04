import Foundation

/// One word of a shell command line, after quote and escape processing.
public struct ShellToken: Equatable, Sendable {
    /// The word with all quoting removed.
    public var text: String
    /// Whether any part of the word was quoted. `-H` and `'-H'` differ here but
    /// not in `text`; the parser uses it only for diagnostics.
    public var wasQuoted: Bool

    public init(text: String, wasQuoted: Bool = false) {
        self.text = text
        self.wasQuoted = wasQuoted
    }
}

public enum ShellTokenizerError: Error, Equatable, CustomStringConvertible {
    case unterminatedQuote(String)

    public var description: String {
        switch self {
        case .unterminatedQuote(let kind):
            return "The command ends in the middle of a \(kind) string."
        }
    }
}

/// Splits a shell command line into words the way `bash` would, minus the parts
/// no "Copy as cURL" output ever uses (expansion, substitution, redirection).
///
/// Handles: unquoted backslash escapes, backslash-newline continuations,
/// `'single'`, `"double"`, `$'ANSI-C'` and `$"..."` quoting, and adjacent
/// quoting that concatenates into one word (`'it'\''s'`).
public enum ShellTokenizer {
    public static func tokenize(_ input: String) throws -> [ShellToken] {
        var scanner = Scanner(Array(input.unicodeScalars))
        return try scanner.run()
    }

    private struct Scanner {
        let scalars: [Unicode.Scalar]
        var index = 0
        var tokens: [ShellToken] = []
        var current = ""
        var started = false
        var quoted = false

        init(_ scalars: [Unicode.Scalar]) { self.scalars = scalars }

        var isAtEnd: Bool { index >= scalars.count }
        func peek(_ offset: Int = 0) -> Unicode.Scalar? {
            let i = index + offset
            return i < scalars.count ? scalars[i] : nil
        }

        mutating func run() throws -> [ShellToken] {
            while let scalar = peek() {
                switch scalar {
                case " ", "\t", "\n", "\r":
                    flush()
                    index += 1
                case "\\":
                    index += 1
                    try consumeUnquotedEscape()
                case "'":
                    index += 1
                    try consumeSingleQuoted()
                case "\"":
                    index += 1
                    try consumeDoubleQuoted()
                case "$" where peek(1) == "'":
                    index += 2
                    try consumeANSICQuoted()
                case "$" where peek(1) == "\"":
                    index += 2
                    try consumeDoubleQuoted()
                default:
                    append(scalar)
                    index += 1
                }
            }
            flush()
            return tokens
        }

        mutating func flush() {
            if started {
                tokens.append(ShellToken(text: current, wasQuoted: quoted))
            }
            current = ""
            started = false
            quoted = false
        }

        mutating func append(_ scalar: Unicode.Scalar) {
            current.unicodeScalars.append(scalar)
            started = true
        }

        mutating func append(_ string: String) {
            current += string
            started = true
        }

        /// A backslash outside quotes escapes the next character; before a
        /// newline it is a line continuation and both characters vanish.
        mutating func consumeUnquotedEscape() throws {
            guard let next = peek() else {
                append("\\" as Unicode.Scalar)   // trailing lone backslash: keep it literal
                return
            }
            if next == "\n" {
                index += 1
            } else if next == "\r" {
                index += 1
                if peek() == "\n" { index += 1 }
            } else {
                append(next)
                index += 1
            }
        }

        mutating func consumeSingleQuoted() throws {
            started = true
            quoted = true
            while let scalar = peek() {
                if scalar == "'" {
                    index += 1
                    return
                }
                append(scalar)
                index += 1
            }
            throw ShellTokenizerError.unterminatedQuote("'…'")
        }

        mutating func consumeDoubleQuoted() throws {
            started = true
            quoted = true
            while let scalar = peek() {
                if scalar == "\"" {
                    index += 1
                    return
                }
                if scalar == "\\", let next = peek(1) {
                    switch next {
                    case "\n":
                        index += 2
                        continue
                    case "\"", "\\", "$", "`":
                        append(next)
                        index += 2
                        continue
                    default:
                        append("\\" as Unicode.Scalar)
                        append(next)
                        index += 2
                        continue
                    }
                }
                append(scalar)
                index += 1
            }
            throw ShellTokenizerError.unterminatedQuote("\"…\"")
        }

        /// `$'…'` — bash's ANSI-C quoting. Decoded as bytes so that the raw
        /// UTF-8 escapes browsers emit (`$'caf\xc3\xa9'`) come back as text.
        mutating func consumeANSICQuoted() throws {
            started = true
            quoted = true
            var bytes: [UInt8] = []

            func appendScalar(_ scalar: Unicode.Scalar) {
                bytes.append(contentsOf: Array(String(scalar).utf8))
            }

            while let scalar = peek() {
                if scalar == "'" {
                    index += 1
                    append(String(decoding: bytes, as: UTF8.self))
                    return
                }
                guard scalar == "\\", let next = peek(1) else {
                    appendScalar(scalar)
                    index += 1
                    continue
                }
                index += 2
                switch next {
                case "a": bytes.append(0x07)
                case "b": bytes.append(0x08)
                case "e", "E": bytes.append(0x1B)
                case "f": bytes.append(0x0C)
                case "n": bytes.append(0x0A)
                case "r": bytes.append(0x0D)
                case "t": bytes.append(0x09)
                case "v": bytes.append(0x0B)
                case "\\": bytes.append(0x5C)
                case "'": bytes.append(0x27)
                case "\"": bytes.append(0x22)
                case "?": bytes.append(0x3F)
                case "x":
                    if let value = readHex(maxDigits: 2) { bytes.append(UInt8(value)) }
                    else { bytes.append(0x5C); bytes.append(0x78) }
                case "u":
                    if let value = readHex(maxDigits: 4), let s = Unicode.Scalar(value) { appendScalar(s) }
                case "U":
                    if let value = readHex(maxDigits: 8), let s = Unicode.Scalar(value) { appendScalar(s) }
                case "0", "1", "2", "3", "4", "5", "6", "7":
                    index -= 1
                    if let value = readOctal(maxDigits: 3) { bytes.append(UInt8(truncatingIfNeeded: value)) }
                case "c":
                    if let control = peek() {
                        index += 1
                        let upper = String(control).uppercased().unicodeScalars.first?.value ?? 0
                        bytes.append(UInt8(truncatingIfNeeded: Int(upper) ^ 0x40))
                    }
                default:
                    bytes.append(0x5C)
                    appendScalar(next)
                }
            }
            throw ShellTokenizerError.unterminatedQuote("$'…'")
        }

        mutating func readHex(maxDigits: Int) -> UInt32? {
            var digits = ""
            while digits.count < maxDigits, let scalar = peek(), scalar.isASCIIHexDigit {
                digits.unicodeScalars.append(scalar)
                index += 1
            }
            return digits.isEmpty ? nil : UInt32(digits, radix: 16)
        }

        mutating func readOctal(maxDigits: Int) -> UInt32? {
            var digits = ""
            while digits.count < maxDigits, let scalar = peek(), scalar.isASCIIOctalDigit {
                digits.unicodeScalars.append(scalar)
                index += 1
            }
            return digits.isEmpty ? nil : UInt32(digits, radix: 8)
        }
    }
}

private extension Unicode.Scalar {
    var isASCIIHexDigit: Bool {
        switch self {
        case "0"..."9", "a"..."f", "A"..."F": return true
        default: return false
        }
    }

    var isASCIIOctalDigit: Bool {
        ("0"..."7").contains(self)
    }
}
