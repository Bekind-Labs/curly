import XCTest
@testable import CurlKit

final class CurlGeneratorTests: XCTestCase {
    private func generate(_ command: String, style: CurlStyle = .singleLine) throws -> String {
        CurlGenerator.generate(try CurlParser.parse(command), style: style)
    }

    // MARK: Layout

    func testSingleLineHasNoLineBreaks() throws {
        let output = try generate(Fixtures.load("chrome/get-query.sh"))
        XCTAssertFalse(output.contains("\n"))
        XCTAssertTrue(output.hasPrefix("curl "))
    }

    func testMultiLinePutsOneFlagPerLineWithContinuations() throws {
        let output = try generate("curl https://x -H 'a: 1' -H 'b: 2' --compressed", style: .multiLine)
        let lines = output.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0], "curl 'https://x' \\")
        XCTAssertEqual(lines[1], "  -H 'a: 1' \\")
        XCTAssertFalse(lines.last!.hasSuffix("\\"), "the last line must not dangle a continuation")
    }

    func testEmptyRequestIsJustCurl() {
        XCTAssertEqual(CurlGenerator.generate(CurlRequest(url: URLParts(scheme: "", host: ""))), "curl")
    }

    // MARK: Quoting

    func testOrdinaryValuesAreSingleQuoted() throws {
        XCTAssertTrue(try generate("curl https://example.com/a?b=c").contains("'https://example.com/a?b=c'"))
    }

    func testSimpleWordsAreLeftUnquoted() throws {
        XCTAssertTrue(try generate("curl https://x -X PATCH").contains("-X PATCH"))
    }

    func testEmbeddedSingleQuoteUsesTheShellSplice() throws {
        let request = try CurlParser.parse("curl https://x --data-raw $'Ada O\\'Brien'")
        let output = CurlGenerator.generate(request, style: .singleLine)
        XCTAssertTrue(output.contains("'Ada O'\\''Brien'"), output)
        // and it survives a trip back through the tokenizer
        XCTAssertEqual(try CurlParser.parse(output).bodyText, "Ada O'Brien")
    }

    func testControlCharactersUseANSICQuoting() throws {
        var request = CurlRequest(url: URLParts(text: "https://x"))
        request.bodyParts = [BodyPart(kind: .dataRaw, value: "one\ntwo\tthree")]
        let output = CurlGenerator.generate(request, style: .singleLine)
        XCTAssertTrue(output.contains("$'one\\ntwo\\tthree'"), output)
        XCTAssertEqual(try CurlParser.parse(output).bodyText, "one\ntwo\tthree")
    }

    func testEmptyValueIsQuoted() {
        var request = CurlRequest(url: URLParts(text: "https://x"))
        request.bodyParts = [BodyPart(kind: .data, value: "")]
        XCTAssertTrue(CurlGenerator.generate(request, style: .singleLine).contains("--data ''"))
    }

    // MARK: What goes in, in what order

    func testFlagOrderIsUrlMethodHeadersCookiesAuthBodyOptions() throws {
        let command = "curl https://x --compressed -u ada:pw -H 'a: 1' -b 'c=2' -X POST --data-raw 'z'"
        let output = try generate(command)
        let positions = ["'https://x'", "-X POST", "-H 'a: 1'", "-b 'c=2'", "-u 'ada:pw'", "--data-raw z", "--compressed"]
            .map { output.range(of: $0)!.lowerBound }
        XCTAssertEqual(positions, positions.sorted(), output)
    }

    func testUrlFlagSpellingIsKept() throws {
        XCTAssertTrue(try generate("curl --url 'https://x/a'").contains("--url 'https://x/a'"))
    }

    func testCookiesComeBackOutTheWayTheyWentIn() throws {
        XCTAssertTrue(try generate("curl https://x -H 'cookie: a=1; b=2'").contains("-H 'cookie: a=1; b=2'"))
        XCTAssertTrue(try generate("curl https://x -b 'a=1; b=2'").contains("-b 'a=1; b=2'"))
    }

    func testDisabledRowsAreLeftOut() throws {
        var request = try CurlParser.parse("curl 'https://x/?a=1&b=2' -H 'a: 1' -H 'b: 2' -b 'c=3; d=4' --compressed")
        request.headers[1].isEnabled = false
        request.url.query[0].isEnabled = false
        request.cookieSections[0].cookies[0].isEnabled = false
        request.options[0].isEnabled = false
        let output = CurlGenerator.generate(request, style: .singleLine)
        XCTAssertTrue(output.contains("-H 'a: 1'"))
        XCTAssertFalse(output.contains("-H 'b: 2'"))
        XCTAssertFalse(output.contains("a=1"))
        XCTAssertTrue(output.contains("b=2"))
        XCTAssertTrue(output.contains("-b 'd=4'"))
        XCTAssertFalse(output.contains("--compressed"))
    }

    func testDisablingEveryCookieDropsTheWholeFlag() throws {
        var request = try CurlParser.parse("curl https://x -b 'c=3'")
        request.cookieSections[0].cookies[0].isEnabled = false
        XCTAssertEqual(CurlGenerator.generate(request, style: .singleLine), "curl 'https://x'")
    }

    func testUnrecognisedFlagsAreWrittenBackOut() throws {
        let output = try generate("curl https://x --future-flag --other=7")
        XCTAssertTrue(output.contains("--future-flag"))
        XCTAssertTrue(output.contains("--other 7"))
    }

    func testExtraArgumentsAreWrittenBackOut() throws {
        XCTAssertTrue(try generate("curl https://a.example https://b.example").contains("'https://b.example'"))
    }

    // MARK: Linking fields to tokens

    private func substring(_ script: CurlScript, _ ref: ElementRef) -> [String] {
        script.ranges(for: ref).map { range in
            let text = Array(script.text)
            return String(text[range])
        }
    }

    func testEachPartOfTheCommandIsLinkedBackToItsField() throws {
        let request = try CurlParser.parse(
            "curl 'https://api.example.com:8443/v1/items?limit=25' -X POST -H 'accept: */*' -b 'sid=9' --data-raw 'hi' --compressed"
        )
        let script = CurlGenerator.script(request, style: .singleLine)

        XCTAssertEqual(substring(script, .command), ["curl"])
        XCTAssertEqual(substring(script, .url), ["'https://api.example.com:8443/v1/items?limit=25'"])
        XCTAssertEqual(substring(script, .urlScheme), ["https"])
        XCTAssertEqual(substring(script, .urlHost), ["api.example.com"])
        XCTAssertEqual(substring(script, .urlPort), ["8443"])
        XCTAssertEqual(substring(script, .urlPath), ["/v1/items"])
        XCTAssertEqual(substring(script, .queryItem(request.url.query[0].id)), ["limit=25"])
        XCTAssertEqual(substring(script, .method), ["-X POST"])
        XCTAssertEqual(substring(script, .header(request.headers[0].id)), ["-H 'accept: */*'"])
        XCTAssertEqual(substring(script, .cookieSection(request.cookieSections[0].id)), ["-b 'sid=9'"])
        XCTAssertEqual(substring(script, .cookie(request.allCookies[0].id)), ["sid=9"])
        XCTAssertEqual(substring(script, .bodyPart(request.bodyParts[0].id)), ["--data-raw hi"])
        XCTAssertEqual(substring(script, .body), ["--data-raw hi"])
        XCTAssertEqual(substring(script, .option(request.options[0].id)), ["--compressed"])
    }

    func testAuthIsLinkedForBothSpellings() throws {
        let flagScript = CurlGenerator.script(try CurlParser.parse("curl https://x -u ada:pw"), style: .singleLine)
        XCTAssertEqual(substring(flagScript, .auth), ["-u 'ada:pw'"])

        let headerScript = CurlGenerator.script(
            try CurlParser.parse("curl https://x -H 'Authorization: Bearer abc'"), style: .singleLine
        )
        XCTAssertEqual(substring(headerScript, .auth), ["-H 'Authorization: Bearer abc'"])
    }

    func testRangesAreValidForTheMultiLineStyleToo() throws {
        let request = try CurlParser.parse(Fixtures.load("chrome/post-json-cookies.sh"))
        let script = CurlGenerator.script(request, style: .multiLine)
        let characters = Array(script.text)
        for segment in script.segments {
            XCTAssertTrue(segment.range.lowerBound >= 0 && segment.range.upperBound <= characters.count)
        }
        XCTAssertEqual(substring(script, .urlHost), ["api.example.com"])
    }
}
