import Foundation

/// Which part of the request a stretch of the generated command came from.
///
/// This is what makes the two halves of the window talk to each other: focus a
/// field, look up its ref, highlight the tokens.
public enum ElementRef: Hashable, Sendable {
    case command
    case url
    case urlScheme
    case urlHost
    case urlPort
    case urlPath
    case urlQuery
    case queryItem(UUID)
    case method
    case header(UUID)
    case cookieSection(UUID)
    case cookie(UUID)
    case auth
    case body
    case bodyPart(UUID)
    case option(UUID)
    case extraArgument(Int)
}

/// A generated curl command, plus a map from each stretch of it back to the
/// field it came from.
public struct CurlScript: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        /// Character offsets into `text`.
        public var range: Range<Int>
        public var ref: ElementRef

        public init(range: Range<Int>, ref: ElementRef) {
            self.range = range
            self.ref = ref
        }
    }

    public var text: String
    public var segments: [Segment]

    public init(text: String, segments: [Segment]) {
        self.text = text
        self.segments = segments
    }

    public func ranges(for ref: ElementRef) -> [Range<Int>] {
        segments.filter { $0.ref == ref }.map(\.range)
    }

    /// The same ranges as `String.Index` ranges, ready for an `AttributedString`.
    public func stringRanges(for ref: ElementRef) -> [Range<String.Index>] {
        ranges(for: ref).compactMap { range in
            guard
                let lower = text.index(text.startIndex, offsetBy: range.lowerBound, limitedBy: text.endIndex),
                let upper = text.index(text.startIndex, offsetBy: range.upperBound, limitedBy: text.endIndex)
            else { return nil }
            return lower..<upper
        }
    }
}

/// How the command is laid out.
public enum CurlStyle: String, CaseIterable, Sendable {
    /// One flag per line, joined with `\` continuations — what browsers copy.
    case multiLine
    /// Everything on one line, which is easier to paste into a chat window.
    case singleLine
}
