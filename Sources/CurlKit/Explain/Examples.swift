import Foundation

/// Ready-made commands for the "Load an example" button, for when there is no
/// browser handy to copy one out of.
public struct Example: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let command: String

    public init(id: String, title: String, summary: String, command: String) {
        self.id = id
        self.title = title
        self.summary = summary
        self.command = command
    }

    public var request: CurlRequest {
        (try? CurlParser.parse(command)) ?? CurlRequest()
    }
}

public enum Examples {
    public static let all: [Example] = [
        Example(
            id: "search",
            title: "Looking something up",
            summary: "A GET request with a search term in the query string.",
            command: """
            curl 'https://api.example.com/v1/search?q=sea%20shells&page=2' \\
              -H 'accept: application/json' \\
              -H 'accept-language: en-GB,en;q=0.9' \\
              -H 'cookie: session=abc123; theme=dark' \\
              --compressed
            """
        ),
        Example(
            id: "json-post",
            title: "Sending some JSON",
            summary: "A POST request with a JSON body and cookies, as Chrome copies it.",
            command: """
            curl 'https://api.example.com/v1/notes' \\
              -H 'accept: */*' \\
              -H 'content-type: application/json' \\
              -H 'cookie: session=abc123; csrf=9f8e7d6c' \\
              -H 'origin: https://app.example.com' \\
              --data-raw '{"title":"Hello","body":"My first note","tags":["new"]}' \\
              --compressed
            """
        ),
        Example(
            id: "form-post",
            title: "Filling in a form",
            summary: "A POST request with form fields, the way an ordinary web page sends them.",
            command: """
            curl 'https://app.example.com/login' \\
              -X 'POST' \\
              -H 'Content-Type: application/x-www-form-urlencoded' \\
              -H 'Cookie: visitor=42' \\
              --data-binary 'user=ada&password=L0vel%40ce&remember=on'
            """
        ),
        Example(
            id: "token",
            title: "Signing in with a token",
            summary: "A request that proves who you are with a bearer token.",
            command: """
            curl 'https://api.example.com/v1/me' \\
              -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.cGF5bG9hZA.signature' \\
              -H 'accept: application/json' \\
              -L
            """
        ),
        Example(
            id: "local",
            title: "Poking a local server",
            summary: "A HEAD request to something running on your own machine.",
            command: "curl --url 'http://localhost:8080/health' -I -k"
        ),
    ]

    public static var first: Example { all[0] }
}
