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

    private static func catalogURL(_ language: String) -> URL {
        repositoryRoot.appendingPathComponent("Sources/curly/Resources/\(language).lproj/Localizable.strings")
    }

    /// The hand-written translations. Each must cover every English key.
    private static let translations = ["ja"]

    private func loadCatalog(_ language: String = "en") throws -> [String: String] {
        let text = try String(contentsOf: Self.catalogURL(language), encoding: .utf8)
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

    func testEveryExampleIsInTheCatalog() throws {
        let catalog = try loadCatalog()
        for example in Examples.all {
            XCTAssertEqual(catalog["example." + example.id + ".title"], example.title, example.id)
        }
    }

    func testTranslationsCoverEveryEnglishKey() throws {
        let english = try loadCatalog()
        for language in Self.translations {
            let translated = try loadCatalog(language)
            let missing = Set(english.keys).subtracting(translated.keys).sorted()
            let stale = Set(translated.keys).subtracting(english.keys).sorted()
            XCTAssertEqual(missing, [], "\(language) is missing these keys")
            XCTAssertEqual(stale, [], "\(language) has keys English no longer uses")
        }
    }

    /// A translation that drops or adds a `%@` would crash `String(format:)`
    /// or show the wrong thing, so the placeholders must match the English.
    func testTranslationsKeepTheirPlaceholders() throws {
        let english = try loadCatalog()
        for language in Self.translations {
            let translated = try loadCatalog(language)
            for (key, value) in english {
                guard let other = translated[key] else { continue }
                XCTAssertEqual(Self.placeholders(in: other), Self.placeholders(in: value), "\(language): \(key)")
            }
        }
    }

    private static func placeholders(in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "%[@d]") else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range)
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
            .sorted()
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
