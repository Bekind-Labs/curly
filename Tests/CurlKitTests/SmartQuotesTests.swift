import XCTest
@testable import CurlKit

final class SmartQuotesTests: XCTestCase {
    func testPlainTextIsLeftAlone() {
        XCTAssertFalse(SmartQuotes.arePresent(in: #"{"a":1}"#))
        XCTAssertEqual(SmartQuotes.straighten(#"{"a":1}"#), #"{"a":1}"#)
    }

    func testCurlyQuotesAreStraightened() {
        XCTAssertTrue(SmartQuotes.arePresent(in: "{\u{201C}a\u{201D}:1}"))
        XCTAssertEqual(SmartQuotes.straighten("{\u{201C}a\u{201D}:1}"), #"{"a":1}"#)
        XCTAssertEqual(SmartQuotes.straighten("it\u{2019}s"), "it's")
    }

    func testOtherPunctuationSurvives() {
        // An em dash or an ellipsis in a body is the author's, not the keyboard's.
        let text = "a — b … c"
        XCTAssertEqual(SmartQuotes.straighten(text), text)
        XCTAssertFalse(SmartQuotes.arePresent(in: text))
    }

    func testTheOfferIsOnlyMadeWhenItWouldActuallyHelp() {
        let mangled = "{\u{201C}name\u{201D}: \u{201C}Ada\u{201D}}"
        XCTAssertFalse(JSONFormatter.isValid(mangled))
        XCTAssertTrue(SmartQuotes.straighteningWouldFixJSON(mangled))
        XCTAssertTrue(JSONFormatter.isValid(SmartQuotes.straighten(mangled)))

        // Already fine: nothing to offer.
        XCTAssertFalse(SmartQuotes.straighteningWouldFixJSON(#"{"a":1}"#))
        // Curly quotes inside a perfectly valid JSON *string* are real content.
        XCTAssertFalse(SmartQuotes.straighteningWouldFixJSON(#"{"quote":"“hi”"}"#))
        // Broken for some other reason: straightening will not save it.
        XCTAssertFalse(SmartQuotes.straighteningWouldFixJSON("{\u{201C}a\u{201D}: }"))
    }

    func testARealisticMangledBodyRoundTripsBackIntoACommand() throws {
        let mangled = "{\u{201C}title\u{201D}:\u{201C}Ada\u{2019}s note\u{201D}}"
        var request = try CurlParser.parse("curl https://x -H 'content-type: application/json'")
        request.setBodyText(SmartQuotes.straighten(mangled))
        XCTAssertTrue(request.bodyIsJSON)
        XCTAssertEqual(request.bodyText, #"{"title":"Ada's note"}"#)

        // And it survives being written out and read back.
        let reparsed = try CurlParser.parse(CurlGenerator.generate(request))
        XCTAssertEqual(reparsed.bodyText, request.bodyText)
    }
}
