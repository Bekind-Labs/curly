import XCTest
@testable import CurlKit

/// Guards the promise that every user-facing string lives in the catalog, so
/// curly can be translated later without hunting through the views.
///
/// Run `make strings` if one of these fails.
final class StringCatalogTests: XCTestCase {
    private static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // CurlKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root

    private static let catalogURL = catalogURL(for: "en")

    /// Everything curly ships beyond English.
    private static let translations = ["ja", "ko"]

    private static func catalogURL(for locale: String) -> URL {
        repositoryRoot
            .appendingPathComponent("Sources/curly/Resources/\(locale).lproj/Localizable.strings")
    }

    private func loadCatalog(_ locale: String = "en") throws -> [String: String] {
        let text = try String(contentsOf: Self.catalogURL(for: locale), encoding: .utf8)
        var entries: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), trimmed.hasSuffix(";") else { continue }
            guard let separator = trimmed.range(of: "\" = \"") else { continue }
            let key = String(trimmed[trimmed.index(after: trimmed.startIndex)..<separator.lowerBound])
            let rawValue = trimmed[separator.upperBound..<trimmed.index(trimmed.endIndex, offsetBy: -2)]
            entries[key] = unescape(String(rawValue))
        }
        return entries
    }

    private func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    func testCatalogExists() throws {
        let catalog = try loadCatalog()
        XCTAssertGreaterThan(catalog.count, 100, "the string catalog looks empty")
    }

    func testEveryExplanationIsInTheCatalog() throws {
        let catalog = try loadCatalog()
        for explanation in Explanation.allCases {
            XCTAssertEqual(catalog[explanation.key], explanation.text, explanation.key)
            XCTAssertEqual(catalog[explanation.key + ".title"], explanation.title, explanation.key)
        }
    }

    func testEveryOptionExplanationIsInTheCatalog() throws {
        let catalog = try loadCatalog()
        for spec in CurlOptionCatalog.all {
            XCTAssertEqual(catalog["option." + spec.long], spec.explanation, spec.long)
        }
    }

    /// Scans the app's own source for `L("key", "English")` and checks each one
    /// made it into the catalog with the same English.
    func testEveryStringInTheAppIsInTheCatalog() throws {
        let catalog = try loadCatalog()
        let sources = Self.repositoryRoot.appendingPathComponent("Sources/curly")
        guard let walker = FileManager.default.enumerator(atPath: sources.path) else {
            return XCTFail("could not read \(sources.path)")
        }

        var checked = 0
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(relative), encoding: .utf8)
            for (key, english) in Self.localisedCalls(in: text) {
                XCTAssertEqual(catalog[key], english, "\(key) in \(relative)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 40, "the scanner found suspiciously few strings")
    }

    // MARK: Translations

    /// Every language has to answer for every key. A key that is merely
    /// missing would fall back to English at runtime, but it would also mean
    /// a translator never saw it.
    func testEveryLanguageCoversEveryKey() throws {
        let english = Set(try loadCatalog().keys)
        for locale in Self.translations {
            let translated = Set(try loadCatalog(locale).keys)
            XCTAssertEqual(
                translated.symmetricDifference(english),
                [],
                "\(locale) is out of step with English — run `make strings`"
            )
        }
    }

    /// `make strings` marks an entry whose English has moved on since it was
    /// translated. A stale translation is worse than a missing one: it is
    /// confidently wrong.
    func testNoTranslationIsStaleOrMissing() throws {
        for locale in Self.translations {
            let text = try String(contentsOf: Self.catalogURL(for: locale), encoding: .utf8)
            XCTAssertFalse(
                text.contains("TODO: translate"),
                "\(locale) has untranslated strings"
            )
            XCTAssertFalse(
                text.contains("STALE:"),
                "\(locale) has translations whose English changed — retranslate and re-run `make strings`"
            )
        }
    }

    /// A translation that drops or adds a %@ or %d crashes `String(format:)`
    /// rather than merely reading oddly, so the placeholders have to match.
    func testFormatPlaceholdersMatchEnglish() throws {
        let english = try loadCatalog()
        for locale in Self.translations {
            let translated = try loadCatalog(locale)
            for (key, source) in english {
                guard let text = translated[key] else { continue }
                XCTAssertEqual(
                    Self.placeholders(in: source).sorted(),
                    Self.placeholders(in: text).sorted(),
                    "\(locale) \(key): placeholders differ from English"
                )
            }
        }
    }

    private static func placeholders(in text: String) -> [String] {
        let pattern = "%(?:[0-9]+\\$)?[@dfsu]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    /// A small scanner for `L("…", "…")`, tolerating the two literals sitting
    /// on separate lines.
    static func localisedCalls(in source: String) -> [(String, String)] {
        let literal = "\"((?:[^\"\\\\]|\\\\.)*)\""
        let pattern = "\\bL\\(\\s*\(literal)\\s*,\\s*\(literal)\\s*\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        else { return [] }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard
                let keyRange = Range(match.range(at: 1), in: source),
                let valueRange = Range(match.range(at: 2), in: source)
            else { return nil }
            return (String(source[keyRange]), unescapeSwift(String(source[valueRange])))
        }
    }

    private static func unescapeSwift(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
