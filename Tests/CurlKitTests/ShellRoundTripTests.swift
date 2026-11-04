import XCTest
@testable import CurlKit

/// The end-to-end promise: a command curly writes out runs in a real shell and
/// hands curl exactly the arguments the original command did.
///
/// A stub `curl` on `PATH` records its own argv, and the two runs are compared.
/// Skipped where there is no `/bin/bash` to run.
final class ShellRoundTripTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/bin/bash"))
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("curly-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        // A stand-in for curl that writes each argument on its own line.
        let stub = scratch.appendingPathComponent("curl")
        try """
        #!/bin/bash
        for argument in "$@"; do printf '%s\\n' "$argument"; done
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    /// Runs `command` through bash with the stub on PATH and returns curl's argv.
    private func arguments(of command: String) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = scratch.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: data, as: UTF8.self)
        var lines = output.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// curl does not care what order its flags arrive in, and curly reorders
    /// them on purpose, so compare the multisets.
    private func assertSameArguments(
        _ original: [String],
        _ regenerated: [String],
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            original.sorted(),
            regenerated.sorted(),
            label,
            file: file,
            line: line
        )
    }

    func testEveryFixtureRunsToTheSameArguments() throws {
        for path in try Fixtures.all {
            let original = try Fixtures.load(path)
            let request = try CurlParser.parse(original)
            let fromShell = try arguments(of: original)
            XCTAssertFalse(fromShell.isEmpty, "fixture \(path) produced no arguments")

            for style in CurlStyle.allCases {
                let regenerated = CurlGenerator.generate(request, style: style)
                assertSameArguments(fromShell, try arguments(of: regenerated), "\(path) in \(style)")
            }
        }
    }

    /// The headline case from the brief: Chrome's "Copy as cURL" of a POST with
    /// a JSON body and cookies, edited and copied back out.
    func testChromeJSONPostSurvivesAnEdit() throws {
        let original = try Fixtures.load("chrome/post-json-cookies.sh")
        var request = try CurlParser.parse(original)

        // Everything is where a beginner would look for it.
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.host, "api.example.com")
        XCTAssertEqual(request.url.path, "/v1/widgets")
        XCTAssertEqual(request.url.query.map(\.name), ["draft"])
        XCTAssertEqual(request.allCookies.map(\.name), ["session", "csrf"])
        XCTAssertEqual(request.contentTypeBase, "application/json")
        XCTAssertTrue(request.bodyIsJSON)
        XCTAssertTrue(request.isOptionEnabled("--compressed"))

        // Unedited, it hands curl exactly what Chrome's command did.
        assertSameArguments(
            try arguments(of: original),
            try arguments(of: CurlGenerator.generate(request, style: .multiLine)),
            "unedited"
        )

        // Now change things the way a newbie would, and check the shell agrees.
        request.allCookiesSetting(name: "session", to: "zzz999")
        request.headers.append(Header(name: "X-Curly", value: "hello there"))
        request.setBodyText("{\"name\":\"Wobble's thing\",\"count\":4}")

        let edited = try arguments(of: CurlGenerator.generate(request, style: .multiLine))
        XCTAssertTrue(edited.contains("cookie: session=zzz999; csrf=9f8e7d6c"), edited.description)
        XCTAssertTrue(edited.contains("X-Curly: hello there"))
        XCTAssertTrue(edited.contains("{\"name\":\"Wobble's thing\",\"count\":4}"))
    }

    func testTurningAHeaderOffRemovesItFromWhatCurlSees() throws {
        var request = try CurlParser.parse(Fixtures.load("chrome/get-query.sh"))
        let argument = request.headers[0].argument
        XCTAssertTrue(try arguments(of: CurlGenerator.generate(request)).contains(argument))

        request.headers[0].isEnabled = false
        XCTAssertFalse(try arguments(of: CurlGenerator.generate(request)).contains(argument))
    }
}

private extension CurlRequest {
    /// Small test helper: change one cookie's value wherever it lives.
    mutating func allCookiesSetting(name: String, to value: String) {
        for sectionIndex in cookieSections.indices {
            for cookieIndex in cookieSections[sectionIndex].cookies.indices
            where cookieSections[sectionIndex].cookies[cookieIndex].name == name {
                cookieSections[sectionIndex].cookies[cookieIndex].value = value
            }
        }
    }
}
