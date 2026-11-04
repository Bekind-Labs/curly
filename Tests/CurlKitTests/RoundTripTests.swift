import XCTest
@testable import CurlKit

/// The two invariants the whole app leans on:
///
///   1. `parse(generate(model)) == model`
///   2. `generate(parse(command))` means the same thing as `command`
///
/// The second is checked by comparing the *parse* of both commands rather than
/// their text, since curly reformats and requotes on purpose.
final class RoundTripTests: XCTestCase {

    // MARK: 1. Model survives a trip through text

    private func assertRoundTrips(
        _ request: CurlRequest,
        style: CurlStyle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let command = CurlGenerator.generate(request, style: style)
        let reparsed = try CurlParser.parse(command)
        XCTAssertEqual(reparsed, request.enabledOnly(), command, file: file, line: line)
    }

    func testEveryFixtureRoundTripsThroughTheModel() throws {
        for path in try Fixtures.all {
            let request = try CurlParser.parse(Fixtures.load(path))
            for style in CurlStyle.allCases {
                try assertRoundTrips(request, style: style)
            }
        }
    }

    func testHandBuiltRequestsRoundTrip() throws {
        var request = CurlRequest(url: URLParts(text: "https://api.example.com:9000/a/b?x=1&y=two"))
        request.explicitMethod = "PATCH"
        request.headers = [
            Header(name: "Accept", value: "application/json"),
            Header(name: "X-Odd", value: "a 'quoted' value"),
            Header(name: "X-Empty", value: ""),
        ]
        request.cookieSections = [
            CookieSection(source: .header(name: "Cookie"), cookies: [Cookie(name: "a", value: "1")]),
            CookieSection(source: .flag(name: "--cookie"), rawValue: "jar.txt"),
        ]
        request.credentials = Credentials(user: "ada", password: "p@ss word")
        request.bodyParts = [BodyPart(kind: .dataRaw, value: "{\"k\": \"line\\nbreak\"}")]
        request.options = [
            CurlOption(flag: "--compressed"),
            CurlOption(flag: "-A", value: "curly/1.0"),
            CurlOption(flag: "--mystery-flag"),
        ]
        request.extraArguments = ["https://second.example"]

        for style in CurlStyle.allCases {
            try assertRoundTrips(request, style: style)
        }
    }

    func testAwkwardValuesRoundTrip() throws {
        let awkward = [
            "plain",
            "",
            "with space",
            "it's",
            "quote\"and'both",
            "new\nline",
            "tab\there",
            "back\\slash",
            "dollar$sign and `ticks`",
            "semi; colon & amp | pipe",
            "emoji 🐚 and café",
            "-leading-dash",
            "{\"json\": [1, 2, 3]}",
        ]
        for value in awkward {
            var request = CurlRequest(url: URLParts(text: "https://x/"))
            request.headers = [Header(name: "X-Test", value: value)]
            request.bodyParts = [BodyPart(kind: .dataRaw, value: value)]
            for style in CurlStyle.allCases {
                try assertRoundTrips(request, style: style, line: #line)
            }
        }
    }

    func testDisabledRowsAreTheOnlyThingLost() throws {
        var request = try CurlParser.parse(Fixtures.load("chrome/post-json-cookies.sh"))
        request.headers[0].isEnabled = false
        request.cookieSections[0].cookies[0].isEnabled = false
        request.url.query[0].isEnabled = false
        try assertRoundTrips(request, style: .multiLine)
    }

    // MARK: 2. Commands keep their meaning

    func testGeneratedCommandMeansTheSameAsTheOriginal() throws {
        for path in try Fixtures.all {
            let original = try Fixtures.load(path)
            let request = try CurlParser.parse(original)
            for style in CurlStyle.allCases {
                let regenerated = CurlGenerator.generate(request, style: style)
                let reparsed = try CurlParser.parse(regenerated)
                XCTAssertEqual(reparsed, request, "fixture \(path) in \(style)")
            }
        }
    }

    func testTheSameRequestLooksTheSameInBothStyles() throws {
        for path in try Fixtures.all {
            let request = try CurlParser.parse(Fixtures.load(path))
            let multi = try CurlParser.parse(CurlGenerator.generate(request, style: .multiLine))
            let single = try CurlParser.parse(CurlGenerator.generate(request, style: .singleLine))
            XCTAssertEqual(multi, single, "fixture \(path)")
        }
    }

    func testGeneratingIsStable() throws {
        for path in try Fixtures.all {
            let request = try CurlParser.parse(Fixtures.load(path))
            let once = CurlGenerator.generate(request, style: .multiLine)
            let twice = CurlGenerator.generate(try CurlParser.parse(once), style: .multiLine)
            XCTAssertEqual(once, twice, "fixture \(path)")
        }
    }

    func testNothingIsEverSilentlyDropped() throws {
        let command = "curl https://x --compressed -L -k --future-flag --another=9 -b jar.txt -T upload.bin"
        let output = CurlGenerator.generate(try CurlParser.parse(command), style: .singleLine)
        for flag in ["--compressed", "-L", "-k", "--future-flag", "--another", "jar.txt", "-T"] {
            XCTAssertTrue(output.contains(flag), "\(flag) went missing from \(output)")
        }
    }

    // MARK: Editing keeps the two halves honest

    func testEditingTheRawURLUpdatesTheParts() {
        var parts = URLParts(text: "https://a.example/one?x=1")
        parts.text = "http://b.example:81/two?y=2&z=3"
        XCTAssertEqual(parts.scheme, "http")
        XCTAssertEqual(parts.host, "b.example")
        XCTAssertEqual(parts.port, "81")
        XCTAssertEqual(parts.path, "/two")
        XCTAssertEqual(parts.query.map(\.name), ["y", "z"])
    }

    func testEditingThePartsUpdatesTheRawURL() {
        var parts = URLParts(text: "https://a.example/one?x=1")
        parts.host = "b.example"
        parts.path = "/two"
        parts.query.append(QueryItem(name: "y", value: "2"))
        XCTAssertEqual(parts.text, "https://b.example/two?x=1&y=2")
    }

    func testSettingTheMethodDropsTheFlagWhenItIsRedundant() throws {
        var request = try CurlParser.parse("curl https://x -X POST --data-raw 'a=1'")
        XCTAssertEqual(request.explicitMethod, "POST")
        request.method = "POST"
        XCTAssertNil(request.explicitMethod, "POST is implied by the body, so -X is just noise")
        request.method = "PUT"
        XCTAssertEqual(request.explicitMethod, "PUT")
    }

    func testEditingBasicCredentialsWritesBackWhereTheyCameFrom() throws {
        var fromFlag = try CurlParser.parse("curl https://x -u ada:old")
        fromFlag.setBasicCredentials(Credentials(user: "ada", password: "new"))
        XCTAssertEqual(fromFlag.credentials?.password, "new")
        XCTAssertNil(fromFlag.header(named: "Authorization"))

        let encoded = Data("ada:old".utf8).base64EncodedString()
        var fromHeader = try CurlParser.parse("curl https://x -H 'Authorization: Basic \(encoded)'")
        fromHeader.setBasicCredentials(Credentials(user: "ada", password: "new"))
        XCTAssertNil(fromHeader.credentials)
        XCTAssertEqual(fromHeader.auth, .basicHeader(Credentials(user: "ada", password: "new")))
    }

    func testEditingFormFieldsRewritesTheBody() throws {
        var request = try CurlParser.parse(Fixtures.load("safari/post-form.sh"))
        var fields = request.formFields
        fields[0].value = "grace hopper"
        request.setFormFields(fields)
        XCTAssertTrue(request.bodyText.hasPrefix("user=grace%20hopper&"))
        XCTAssertEqual(request.formFields[0].value, "grace hopper")
        XCTAssertEqual(request.bodyParts.first?.kind, .dataBinary, "the original flag spelling is kept")
    }

    func testPrettyPrintingAndMinifyingJSONAgree() throws {
        let request = try CurlParser.parse(Fixtures.load("chrome/post-json-cookies.sh"))
        let pretty = try XCTUnwrap(JSONFormatter.prettyPrinted(request.bodyText))
        XCTAssertTrue(pretty.contains("\n"))
        XCTAssertEqual(JSONFormatter.minified(pretty), JSONFormatter.minified(request.bodyText))
        XCTAssertNil(JSONFormatter.validate(pretty))
        XCTAssertNotNil(JSONFormatter.validate("{nope}"))
    }
}
