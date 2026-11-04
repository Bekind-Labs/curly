import Foundation

/// Writes a value back out so that a shell hands curl exactly the same string.
public enum ShellQuoting {
    /// Characters that are safe to leave bare. Deliberately narrow: a value is
    /// only left unquoted when it is a plain word like `POST` or `10`. Quoting
    /// everything else keeps the command copy-and-pasteable and, more to the
    /// point, keeps each value visibly one thing.
    private static let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.")

    public static func quote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        if !value.hasPrefix("-"), value.allSatisfy({ safe.contains($0) }) { return value }
        if value.unicodeScalars.contains(where: isControl) { return ansiCQuoted(value) }
        if value.contains("'") {
            // Close the quote, escape the apostrophe, reopen: 'it'\''s'.
            return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return "'" + value + "'"
    }

    /// True when `quote` simply wrapped the value in a pair of single quotes,
    /// which is what lets the generator map ranges inside the quoted value.
    public static func isPlainlyWrapped(_ value: String, quoted: String) -> Bool {
        quoted == value || quoted == "'" + value + "'"
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || scalar.value == 0x7F
    }

    private static func ansiCQuoted(_ value: String) -> String {
        var result = "$'"
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "'": result += "\\'"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if isControl(scalar) {
                    result += String(format: "\\x%02x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "'"
    }
}
