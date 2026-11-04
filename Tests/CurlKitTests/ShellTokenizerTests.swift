import XCTest
@testable import CurlKit

final class ShellTokenizerTests: XCTestCase {
    private func words(_ input: String) throws -> [String] {
        try ShellTokenizer.tokenize(input).map(\.text)
    }

    func testSplitsOnWhitespace() throws {
        XCTAssertEqual(try words("curl https://example.com"), ["curl", "https://example.com"])
        XCTAssertEqual(try words("  curl   -I   "), ["curl", "-I"])
    }

    func testSingleQuotesAreLiteral() throws {
        XCTAssertEqual(try words("curl 'a b' '-H' 'x: \\n'"), ["curl", "a b", "-H", "x: \\n"])
    }

    func testDoubleQuotesHonourBackslashEscapes() throws {
        XCTAssertEqual(try words("\"a\\\"b\""), ["a\"b"])
        XCTAssertEqual(try words("\"a\\\\b\""), ["a\\b"])
        XCTAssertEqual(try words("\"a\\nb\""), ["a\\nb"])  // \n is not special inside ""
        XCTAssertEqual(try words("\"$HOME\""), ["$HOME"])  // no expansion
    }

    func testAdjacentQuotingConcatenates() throws {
        XCTAssertEqual(try words("a'b'c\"d\""), ["abcd"])
        XCTAssertEqual(try words("'it'\\''s'"), ["it's"])
    }

    func testBackslashNewlineIsALineContinuation() throws {
        let input = "curl 'https://x' \\\n  -H 'a: b' \\\n  --compressed\n"
        XCTAssertEqual(try words(input), ["curl", "https://x", "-H", "a: b", "--compressed"])
    }

    func testCarriageReturnLineContinuation() throws {
        XCTAssertEqual(try words("curl \\\r\n  -I"), ["curl", "-I"])
    }

    func testBareNewlineSeparatesWords() throws {
        XCTAssertEqual(try words("curl\n-I"), ["curl", "-I"])
    }

    func testANSICQuoting() throws {
        XCTAssertEqual(try words("$'line\\nbreak'"), ["line\nbreak"])
        XCTAssertEqual(try words("$'tab\\there'"), ["tab\there"])
        XCTAssertEqual(try words("$'quote\\''"), ["quote'"])
        XCTAssertEqual(try words("$'caf\\u00e9'"), ["café"])
        XCTAssertEqual(try words("$'\\x41\\x42'"), ["AB"])
        XCTAssertEqual(try words("$'\\101'"), ["A"])
        XCTAssertEqual(try words("$'a\\\\b'"), ["a\\b"])
        // UTF-8 arriving as raw hex bytes, which is what bash/Firefox emit.
        XCTAssertEqual(try words("$'caf\\xc3\\xa9'"), ["café"])
    }

    func testDollarDoubleQuoteBehavesLikeDoubleQuote() throws {
        XCTAssertEqual(try words("$\"a b\""), ["a b"])
    }

    func testUnterminatedQuoteThrows() throws {
        XCTAssertThrowsError(try words("curl 'oops"))
        XCTAssertThrowsError(try words("curl \"oops"))
        XCTAssertThrowsError(try words("curl $'oops"))
    }

    func testQuotedEmptyStringIsAWord() throws {
        XCTAssertEqual(try words("curl -d ''"), ["curl", "-d", ""])
    }

    func testTokenRecordsWhetherItWasQuoted() throws {
        let tokens = try ShellTokenizer.tokenize("curl 'x'")
        XCTAssertEqual(tokens.map(\.wasQuoted), [false, true])
    }

    func testLeadingShellPromptIsTokenizedPlainly() throws {
        XCTAssertEqual(try words("$ curl -I"), ["$", "curl", "-I"])
    }

    func testEveryFixtureTokenizesAndStartsWithCurl() throws {
        for path in try Fixtures.all {
            let text = try Fixtures.load(path)
            let tokens = try ShellTokenizer.tokenize(text)
            XCTAssertEqual(tokens.first?.text, "curl", "fixture \(path)")
            XCTAssertFalse(tokens.contains { $0.text.contains("\\\n") }, "fixture \(path)")
        }
    }
}
