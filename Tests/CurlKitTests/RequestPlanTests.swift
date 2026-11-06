import XCTest
@testable import CurlKit

/// Sending is the one thing curly does that it cannot take back, so what goes
/// on the wire is worked out here, in a pure function, and checked.
final class RequestPlanTests: XCTestCase {
    private func plan(_ command: String) throws -> RequestPlan {
        try RequestPlanner.plan(for: try CurlParser.parse(command))
    }

    private func value(_ plan: RequestPlan, _ name: String) -> String? {
        plan.headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    // MARK: The basics

    func testMethodAndAddress() throws {
        let simple = try plan("curl https://api.example.com/v1/items?page=2")
        XCTAssertEqual(simple.method, "GET")
        XCTAssertEqual(simple.url, "https://api.example.com/v1/items?page=2")
        XCTAssertNil(simple.body)
    }

    func testAMissingSchemeBecomesHttpLikeCurl() throws {
        XCTAssertEqual(try plan("curl example.com/thing").url, "http://example.com/thing")
    }

    func testAnAddressIsRequired() {
        XCTAssertThrowsError(try plan("curl -I")) { error in
            XCTAssertEqual(error as? RequestPlanError, .noAddress)
        }
    }

    func testHeadersAreCarriedThrough() throws {
        let planned = try plan("curl https://x -H 'Accept: application/json' -H 'X-Trace: 1'")
        XCTAssertEqual(value(planned, "accept"), "application/json")
        XCTAssertEqual(value(planned, "X-Trace"), "1")
    }

    func testSwitchedOffHeadersAreNotSent() throws {
        var request = try CurlParser.parse("curl https://x -H 'Accept: application/json'")
        request.headers[0].isEnabled = false
        let planned = try RequestPlanner.plan(for: request)
        XCTAssertNil(value(planned, "accept"))
    }

    func testCookiesBecomeOneHeader() throws {
        let planned = try plan("curl https://x -b 'a=1; b=2'")
        XCTAssertEqual(value(planned, "cookie"), "a=1; b=2")
    }

    func testSwitchedOffCookiesAreNotSent() throws {
        var request = try CurlParser.parse("curl https://x -b 'a=1; b=2'")
        request.cookieSections[0].cookies[0].isEnabled = false
        XCTAssertEqual(value(try RequestPlanner.plan(for: request), "cookie"), "b=2")
    }

    func testCookieFilesAreNotGuessedAt() throws {
        let planned = try plan("curl https://x -b jar.txt")
        XCTAssertNil(value(planned, "cookie"))
        XCTAssertTrue(planned.warnings.contains { $0.contains("jar.txt") })
    }

    func testUserFlagBecomesABasicAuthorizationHeader() throws {
        let planned = try plan("curl https://x -u ada:secret")
        XCTAssertEqual(value(planned, "authorization"), "Basic " + Data("ada:secret".utf8).base64EncodedString())
    }

    func testUserAgentAndRefererBecomeHeaders() throws {
        let planned = try plan("curl https://x -A 'curly/1.0' -e 'https://example.com'")
        XCTAssertEqual(value(planned, "user-agent"), "curly/1.0")
        XCTAssertEqual(value(planned, "referer"), "https://example.com")
    }

    // MARK: Bodies

    func testJSONBodyIsSentAsWritten() throws {
        let planned = try plan("curl https://x -H 'content-type: application/json' --data-raw '{\"a\":1}'")
        XCTAssertEqual(planned.method, "POST")
        XCTAssertEqual(String(decoding: planned.body ?? Data(), as: UTF8.self), "{\"a\":1}")
        XCTAssertEqual(value(planned, "content-type"), "application/json")
    }

    func testABodyWithoutAContentTypeGetsCurlsDefault() throws {
        let planned = try plan("curl https://x -d 'a=1'")
        XCTAssertEqual(value(planned, "content-type"), "application/x-www-form-urlencoded")
    }

    func testSeveralDataFlagsAreJoinedWithAmpersands() throws {
        let planned = try plan("curl https://x -d 'a=1' -d 'b=2'")
        XCTAssertEqual(String(decoding: planned.body ?? Data(), as: UTF8.self), "a=1&b=2")
    }

    func testDataUrlEncodeEscapesItsContent() throws {
        let planned = try plan("curl https://x --data-urlencode 'q=swift ui'")
        XCTAssertEqual(String(decoding: planned.body ?? Data(), as: UTF8.self), "q=swift%20ui")
    }

    func testGetFlagMovesTheDataOntoTheAddress() throws {
        let planned = try plan("curl -G https://api.example.com/search --data-urlencode 'q=swift ui'")
        XCTAssertEqual(planned.method, "GET")
        XCTAssertNil(planned.body)
        XCTAssertEqual(planned.url, "https://api.example.com/search?q=swift%20ui")
    }

    func testFormFieldsBecomeAMultipartBody() throws {
        let planned = try plan("curl https://x --form-string 'title=Hi' --form-string 'who=Ada'")
        let contentType = try XCTUnwrap(value(planned, "content-type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))

        let boundary = String(contentType.split(separator: "=", maxSplits: 1)[1])
        let text = String(decoding: planned.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"title\""))
        XCTAssertTrue(text.contains("Hi"))
        XCTAssertTrue(text.hasSuffix("--\(boundary)--\r\n"))
    }

    func testAMissingUploadFileIsAnErrorRatherThanAnEmptyField() throws {
        XCTAssertThrowsError(try plan("curl https://x -F 'file=@/nope/missing.pdf'")) { error in
            XCTAssertEqual(error as? RequestPlanError, .unreadableFile("/nope/missing.pdf"))
        }
    }

    func testDataRawTakesAnAtSignLiterally() throws {
        let planned = try plan("curl https://x --data-raw '@not-a-file'")
        XCTAssertEqual(String(decoding: planned.body ?? Data(), as: UTF8.self), "@not-a-file")
    }

    // MARK: Options that change how it is sent

    func testRedirectsAreOnlyFollowedWhenAsked() throws {
        XCTAssertFalse(try plan("curl https://x").followsRedirects)
        XCTAssertTrue(try plan("curl -L https://x").followsRedirects)
    }

    func testInsecureIsCarriedThrough() throws {
        XCTAssertFalse(try plan("curl https://x").skipsCertificateChecks)
        XCTAssertTrue(try plan("curl -k https://x").skipsCertificateChecks)
    }

    func testHeadRequestsAskForHead() throws {
        XCTAssertEqual(try plan("curl -I https://x").method, "HEAD")
    }

    func testTimeouts() throws {
        XCTAssertEqual(try plan("curl https://x --max-time 10").timeout, 10)
        XCTAssertEqual(try plan("curl https://x --connect-timeout 4").timeout, 4)
        XCTAssertNil(try plan("curl https://x").timeout)
    }

    func testFlagsCurlyCannotHonourAreReportedNotIgnored() throws {
        let planned = try plan("curl https://x --proxy http://localhost:3128 --limit-rate 10k --compressed -v")
        XCTAssertEqual(planned.unsupportedOptions, ["--limit-rate", "--proxy"])
        XCTAssertFalse(planned.unsupportedOptions.contains("--compressed"), "URLSession handles this itself")
        XCTAssertFalse(planned.unsupportedOptions.contains("--verbose"), "this only affects what we show")
    }

    func testEveryFixtureCanBePlanned() throws {
        for path in try Fixtures.all where !path.contains("multipart") {
            XCTAssertNoThrow(try RequestPlanner.plan(for: CurlParser.parse(Fixtures.load(path))), path)
        }
    }

    // MARK: Verbosity

    func testVerbosityIsReadFromTheFlags() throws {
        XCTAssertEqual(try CurlParser.parse("curl https://x").verbosity, .normal)
        XCTAssertEqual(try CurlParser.parse("curl -v https://x").verbosity, .verbose)
        XCTAssertEqual(try CurlParser.parse("curl -i https://x").verbosity, .headers)
        XCTAssertEqual(try CurlParser.parse("curl -s https://x").verbosity, .quiet)
    }

    func testSettingVerbosityRewritesTheFlags() throws {
        var request = try CurlParser.parse("curl https://x")
        request.verbosity = .verbose
        XCTAssertTrue(CurlGenerator.generate(request, style: .singleLine).contains("--verbose"))

        request.verbosity = .headers
        let command = CurlGenerator.generate(request, style: .singleLine)
        XCTAssertTrue(command.contains("--include"))
        XCTAssertFalse(command.contains("--verbose"), "the old choice is cleared")

        request.verbosity = .normal
        XCTAssertEqual(CurlGenerator.generate(request, style: .singleLine), "curl 'https://x'")
    }

    func testVerbositySurvivesARoundTrip() throws {
        for verbosity in Verbosity.allCases {
            var request = try CurlParser.parse("curl https://x -H 'a: 1'")
            request.verbosity = verbosity
            let reparsed = try CurlParser.parse(CurlGenerator.generate(request))
            XCTAssertEqual(reparsed.verbosity, verbosity)
            XCTAssertEqual(reparsed, request.enabledOnly())
        }
    }

    func testTheVerboseTranscriptLooksLikeCurls() throws {
        var request = try CurlParser.parse("curl 'https://api.example.com/v1/items?page=2' -H 'Accept: */*'")
        request.verbosity = .verbose
        let lines = try RequestPlanner.plan(for: request).requestTranscript
        XCTAssertEqual(lines[0], "> GET /v1/items?page=2 HTTP/1.1")
        XCTAssertEqual(lines[1], "> Host: api.example.com")
        XCTAssertTrue(lines.contains("> Accept: */*"))
    }
}
