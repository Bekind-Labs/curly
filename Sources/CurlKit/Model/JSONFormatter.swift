import Foundation

/// Pretty-printing and checking for JSON bodies.
public enum JSONFormatter {
    public static func isValid(_ text: String) -> Bool {
        validate(text) == nil
    }

    /// Returns a plain-English complaint, or `nil` when the text is good JSON.
    public static func validate(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "There is nothing here yet." }
        guard let data = trimmed.data(using: .utf8) else { return "This is not text JSON can read." }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return nil
        } catch {
            return (error as NSError).localizedDescription
        }
    }

    /// Lays the JSON out over several lines. Returns `nil` if it is not JSON.
    public static func prettyPrinted(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
            )
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    /// Squeezes the JSON back onto one line, which is what browsers send.
    public static func minified(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
            let compact = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.withoutEscapingSlashes, .sortedKeys]
            )
        else { return nil }
        return String(data: compact, encoding: .utf8)
    }
}
