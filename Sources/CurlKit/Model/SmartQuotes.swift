import Foundation

/// macOS substitutes “curly” quotes for straight ones as you type, which is
/// lovely in a letter and ruinous in a JSON body: `{“a”:1}` is not JSON.
///
/// curly turns the substitution off in its own text fields, but text can still
/// arrive already curled — pasted out of a document, a chat window or a wiki —
/// so it can also be repaired after the fact.
public enum SmartQuotes {
    /// Only the characters macOS's *quote* substitution produces. Dashes and
    /// ellipses are left alone: an em dash in a body is far more likely to be
    /// something the author meant than something the keyboard did.
    private static let replacements: [Character: Character] = [
        "\u{201C}": "\"",   // “ left double
        "\u{201D}": "\"",   // ” right double
        "\u{201E}": "\"",   // „ low double
        "\u{201F}": "\"",   // ‟ reversed double
        "\u{2018}": "'",    // ‘ left single
        "\u{2019}": "'",    // ’ right single
        "\u{201A}": "'",    // ‚ low single
        "\u{201B}": "'",    // ‛ reversed single
        "\u{2032}": "'",    // ′ prime
        "\u{2033}": "\"",   // ″ double prime
    ]

    public static func arePresent(in text: String) -> Bool {
        text.contains { replacements.keys.contains($0) }
    }

    /// Replaces curly quotes with straight ones and leaves everything else be.
    public static func straighten(_ text: String) -> String {
        guard arePresent(in: text) else { return text }
        return String(text.map { replacements[$0] ?? $0 })
    }

    /// True when the text is not JSON now but would be once straightened —
    /// which is exactly the situation worth offering to fix.
    public static func straighteningWouldFixJSON(_ text: String) -> Bool {
        guard arePresent(in: text), !JSONFormatter.isValid(text) else { return false }
        return JSONFormatter.isValid(straighten(text))
    }
}
