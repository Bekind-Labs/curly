import Foundation

/// Access to the real "Copy as cURL" samples checked into `Tests/Fixtures/`.
///
/// They are read straight off disk relative to `#filePath` rather than bundled
/// as SwiftPM resources, so the fixture tree can keep its readable layout.
enum Fixtures {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // CurlKitTests
        .deletingLastPathComponent()   // Tests
        .appendingPathComponent("Fixtures")

    static func load(_ relativePath: String) throws -> String {
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    static var all: [String] {
        get throws {
            let urls = try FileManager.default
                .subpathsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".sh") }
            return urls.sorted()
        }
    }
}
