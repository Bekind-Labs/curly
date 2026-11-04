import XCTest
@testable import CurlKit

final class CurlParserTests: XCTestCase {
    private func parse(_ command: String) throws -> CurlRequest {
        try CurlParser.parse(command)
    }

    // MARK: Shape of the command

    func testRequiresTheCommandToStartWithCurl() {
        XCTAssertThrowsError(try parse("wget https://example.com"))
        XCTAssertThrowsError(try parse(""))
    }

    func testToleratesALeadingShellPrompt() throws {
        XCTAssertEqual(try parse("$ curl https://example.com").url.host, "example.com")
        XCTAssertEqual(try parse("  curl https://example.com  ").url.host, "example.com")
    }

    func testLooksLikeCurlRecognisesPasteableCommands() {
        XCTAssertTrue(CurlParser.looksLikeCurl("curl 'https://x'"))
        XCTAssertTrue(CurlParser.looksLikeCurl("  $ curl -I https://x"))
        XCTAssertFalse(CurlParser.looksLikeCurl("https://x"))
        XCTAssertFalse(CurlParser.looksLikeCurl("curly is a nice word"))
    }

    // MARK: URL

    func testSplitsTheURLIntoParts() throws {
        let request = try parse("curl 'https://api.example.com:8443/v1/items?limit=25&debug#frag'")
        XCTAssertEqual(request.url.scheme, "https")
        XCTAssertEqual(request.url.host, "api.example.com")
        XCTAssertEqual(request.url.port, "8443")
        XCTAssertEqual(request.url.path, "/v1/items")
        XCTAssertEqual(request.url.query.map(\.name), ["limit", "debug"])
        XCTAssertEqual(request.url.query.map(\.value), ["25", nil])
        XCTAssertEqual(request.url.fragment, "frag")
    }

    func testURLFlagIsRemembered() throws {
        let request = try parse("curl --url 'http://localhost:8080/health'")
        XCTAssertTrue(request.url.usesURLFlag)
        XCTAssertEqual(request.url.port, "8080")
    }

    func testQueryValuesKeepTheirEscaping() throws {
        let request = try parse("curl 'https://x/?q=swift%20ui&t=a+b'")
        XCTAssertEqual(request.url.query.map(\.value), ["swift%20ui", "a+b"])
        XCTAssertEqual(URLParts.decode("swift%20ui"), "swift ui")
    }

    // MARK: Method

    func testMethodDefaultsToGet() throws {
        XCTAssertEqual(try parse("curl https://x").method, "GET")
        XCTAssertNil(try parse("curl https://x").explicitMethod)
    }

    func testDataImpliesPost() throws {
        let request = try parse("curl https://x --data-raw 'a=1'")
        XCTAssertEqual(request.method, "POST")
        XCTAssertNil(request.explicitMethod)
    }

    func testHeadFlagImpliesHead() throws {
        XCTAssertEqual(try parse("curl -I https://x").method, "HEAD")
    }

    func testGetFlagKeepsTheMethodGetEvenWithData() throws {
        let request = try parse("curl -G https://x --data-urlencode 'q=hi'")
        XCTAssertEqual(request.method, "GET")
    }

    func testExplicitMethodWins() throws {
        XCTAssertEqual(try parse("curl -X PATCH https://x").method, "PATCH")
        XCTAssertEqual(try parse("curl --request 'DELETE' https://x").explicitMethod, "DELETE")
    }

    // MARK: Headers and cookies

    func testHeadersKeepOrderAndSpelling() throws {
        let request = try parse("curl https://x -H 'accept: */*' -H 'X-Trace: 1'")
        XCTAssertEqual(request.headers.map(\.name), ["accept", "X-Trace"])
        XCTAssertEqual(request.headers.map(\.value), ["*/*", "1"])
        XCTAssertTrue(request.headers.allSatisfy(\.isEnabled))
    }

    func testHeaderWithoutASpaceAfterTheColon() throws {
        let request = try parse("curl https://x -H 'Accept:application/json'")
        XCTAssertEqual(request.headers.first?.name, "Accept")
        XCTAssertEqual(request.headers.first?.value, "application/json")
    }

    func testCookieHeaderBecomesItsOwnSection() throws {
        let request = try parse("curl https://x -H 'cookie: a=1; b=2' -H 'Accept: */*'")
        XCTAssertEqual(request.headers.map(\.name), ["Accept"])
        XCTAssertEqual(request.cookieSections.count, 1)
        XCTAssertEqual(request.cookieSections[0].source, .header(name: "cookie"))
        XCTAssertEqual(request.allCookies.map(\.name), ["a", "b"])
        XCTAssertEqual(request.allCookies.map(\.value), ["1", "2"])
    }

    func testCookieFlagBecomesItsOwnSection() throws {
        let request = try parse("curl https://x -b 'sid=9; theme=dark'")
        XCTAssertEqual(request.cookieSections[0].source, .flag(name: "-b"))
        XCTAssertEqual(request.allCookies.map(\.name), ["sid", "theme"])
    }

    func testCookieFileIsKeptVerbatim() throws {
        let request = try parse("curl https://x -b cookies.txt")
        XCTAssertEqual(request.cookieSections[0].rawValue, "cookies.txt")
        XCTAssertTrue(request.allCookies.isEmpty)
    }

    // MARK: Body

    func testDataFlagsKeepTheirSpelling() throws {
        let request = try parse("curl https://x -d 'a=1' --data-binary 'b=2' --data-raw 'c=3'")
        XCTAssertEqual(request.bodyParts.map(\.kind), [.data, .dataBinary, .dataRaw])
        XCTAssertEqual(request.bodyParts.map(\.value), ["a=1", "b=2", "c=3"])
    }

    func testFormFieldsAreBodyParts() throws {
        let request = try parse("curl https://x -F 'file=@/tmp/a.pdf' --form-string 'title=Hi'")
        XCTAssertEqual(request.bodyParts.map(\.kind), [.form, .formString])
        XCTAssertEqual(request.bodyShape, .multipart)
    }

    func testJSONBodyIsRecognised() throws {
        let request = try parse("curl https://x -H 'content-type: application/json' --data-raw '{\"a\":1}'")
        XCTAssertEqual(request.bodyShape, .text)
        XCTAssertTrue(request.bodyIsJSON)
        XCTAssertEqual(request.contentTypeBase, "application/json")
    }

    func testFormEncodedBodyIsRecognised() throws {
        let request = try parse(
            "curl https://x -H 'content-type: application/x-www-form-urlencoded' --data-raw 'a=1&name=Ada%20L'"
        )
        XCTAssertEqual(request.bodyShape, .formURLEncoded)
        XCTAssertEqual(request.formFields.map(\.name), ["a", "name"])
        XCTAssertEqual(request.formFields.map(\.value), ["1", "Ada L"])
    }

    // MARK: Auth

    func testUserFlagIsReadAsCredentials() throws {
        let request = try parse("curl -u 'ada:L0vel@ce' https://x")
        XCTAssertEqual(request.credentials, Credentials(user: "ada", password: "L0vel@ce"))
        XCTAssertEqual(request.auth, .basicFlag(Credentials(user: "ada", password: "L0vel@ce")))
    }

    func testBasicAuthorizationHeaderIsDecoded() throws {
        let encoded = Data("ada:secret".utf8).base64EncodedString()
        let request = try parse("curl https://x -H 'Authorization: Basic \(encoded)'")
        XCTAssertEqual(request.auth, .basicHeader(Credentials(user: "ada", password: "secret")))
        // The header is still there, because it is still what gets sent.
        XCTAssertNotNil(request.header(named: "authorization"))
    }

    func testBearerTokenIsRecognised() throws {
        let request = try parse("curl https://x -H 'Authorization: Bearer abc.def.ghi'")
        XCTAssertEqual(request.auth, .bearer("abc.def.ghi"))
    }

    // MARK: Options

    func testKnownFlagsBecomeOptions() throws {
        let request = try parse("curl https://x --compressed -L -k")
        XCTAssertEqual(request.options.map(\.flag), ["--compressed", "-L", "-k"])
        XCTAssertTrue(request.options.allSatisfy { !$0.isUnrecognised })
        XCTAssertNotNil(request.options[0].spec?.explanation)
    }

    func testFlagsWithValuesKeepThem() throws {
        let request = try parse("curl https://x -A 'curly/1.0' --max-time 10")
        XCTAssertEqual(request.option("-A")?.value, "curly/1.0")
        XCTAssertEqual(request.option("--max-time")?.value, "10")
    }

    func testLongFlagWithEqualsSign() throws {
        let request = try parse("curl https://x --max-time=30 --proxy=http://localhost:3128")
        XCTAssertEqual(request.option("--max-time")?.value, "30")
        XCTAssertEqual(request.option("--proxy")?.value, "http://localhost:3128")
    }

    func testBundledShortFlags() throws {
        let request = try parse("curl -sSLk https://x")
        XCTAssertEqual(request.options.map(\.flag), ["-s", "-S", "-L", "-k"])
        XCTAssertEqual(request.url.host, "x")
    }

    func testShortFlagWithAttachedValue() throws {
        let request = try parse("curl -H'Accept: */*' https://x")
        XCTAssertEqual(request.headers.first?.name, "Accept")
    }

    func testUnrecognisedFlagsArePreservedNotDropped() throws {
        let request = try parse("curl https://x --future-flag --other=7")
        XCTAssertEqual(request.options.map(\.flag), ["--future-flag", "--other"])
        XCTAssertTrue(request.options[0].isUnrecognised)
        XCTAssertEqual(request.options[1].value, "7")
    }

    func testExtraPositionalArgumentsArePreserved() throws {
        let request = try parse("curl https://a.example https://b.example")
        XCTAssertEqual(request.url.host, "a.example")
        XCTAssertEqual(request.extraArguments, ["https://b.example"])
    }

    // MARK: Real devtools output

    func testChromeGetWithQueryString() throws {
        let request = try CurlParser.parse(Fixtures.load("chrome/get-query.sh"))
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.host, "api.example.com")
        XCTAssertEqual(request.url.path, "/v1/search")
        XCTAssertEqual(request.url.query.map(\.name), ["q", "page", "sort"])
        XCTAssertEqual(request.allCookies.map(\.name), ["session", "theme", "_ga"])
        XCTAssertFalse(request.headers.contains { $0.name.lowercased() == "cookie" })
        XCTAssertTrue(request.isOptionEnabled("--compressed"))
        XCTAssertEqual(
            request.header(named: "sec-ch-ua")?.value,
            "\"Chromium\";v=\"124\", \"Not:A-Brand\";v=\"8\""
        )
    }

    func testChromePostWithJSONBodyAndCookies() throws {
        let request = try CurlParser.parse(Fixtures.load("chrome/post-json-cookies.sh"))
        XCTAssertEqual(request.method, "POST")
        XCTAssertNil(request.explicitMethod)
        XCTAssertEqual(request.url.query.map(\.encoded), ["draft=true"])
        XCTAssertEqual(request.allCookies.map(\.name), ["session", "csrf"])
        XCTAssertTrue(request.bodyIsJSON)
        XCTAssertEqual(request.bodyShape, .text)
        XCTAssertEqual(request.bodyParts.first?.kind, .dataRaw)
    }

    func testSafariPostForm() throws {
        let request = try CurlParser.parse(Fixtures.load("safari/post-form.sh"))
        XCTAssertEqual(request.explicitMethod, "POST")
        XCTAssertEqual(request.bodyParts.first?.kind, .dataBinary)
        XCTAssertEqual(request.bodyShape, .formURLEncoded)
        XCTAssertEqual(request.formFields.map(\.value), ["ada", "L0vel@ce", "on"])
        XCTAssertEqual(request.allCookies.map(\.name), ["visitor"])
    }

    func testFirefoxSingleLinePost() throws {
        let request = try CurlParser.parse(Fixtures.load("firefox/post-json.sh"))
        XCTAssertEqual(request.explicitMethod, "POST")
        XCTAssertTrue(request.isOptionEnabled("--compressed"))
        XCTAssertEqual(request.allCookies.map(\.name), ["session", "tz"])
        XCTAssertTrue(request.bodyIsJSON)
    }

    func testFirefoxANSICQuoting() throws {
        let request = try CurlParser.parse(Fixtures.load("firefox/ansi-c-quoting.sh"))
        XCTAssertEqual(request.allCookies.map(\.value), ["abc123", "café"])
        XCTAssertTrue(request.bodyText.contains("line one\nline two\ttabbed"))
        XCTAssertTrue(request.bodyText.contains("Ada O'Brien"))
    }

    func testBasicAuthFixture() throws {
        let request = try CurlParser.parse(Fixtures.load("misc/basic-auth.sh"))
        XCTAssertEqual(request.credentials?.user, "ada")
        XCTAssertEqual(request.credentials?.password, "L0vel@ce")
        XCTAssertEqual(request.url.path, "/v1/me")
    }

    func testGetWithURLEncodedData() throws {
        let request = try CurlParser.parse(Fixtures.load("misc/get-with-data.sh"))
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.bodyShape, .urlEncodedFields)
        XCTAssertEqual(request.bodyParts.map(\.value), ["q=swift ui", "page=2"])
    }

    func testAssortedFlagsFixture() throws {
        let request = try CurlParser.parse(Fixtures.load("misc/assorted-flags.sh"))
        XCTAssertTrue(request.url.usesURLFlag)
        XCTAssertEqual(request.method, "HEAD")
        XCTAssertEqual(request.option("-A")?.value, "curly/1.0")
        XCTAssertEqual(request.option("--referer")?.value, "https://example.com")
        XCTAssertEqual(request.option("--retry")?.value, "3")
    }

    func testEveryFixtureParses() throws {
        for path in try Fixtures.all {
            XCTAssertNoThrow(try CurlParser.parse(Fixtures.load(path)), "fixture \(path)")
        }
    }
}
