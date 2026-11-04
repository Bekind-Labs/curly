import SwiftUI

/// The handful of shared looks, in one place.
enum Theme {
    /// The field the cursor is in.
    static let focusHighlight = Color.accentColor.opacity(0.28)
    /// Something that just changed.
    static let changeFlash = Color.yellow.opacity(0.65)

    static let cardCorner: CGFloat = 10
    static let rowSpacing: CGFloat = 6
    static let monospaced = Font.system(.body, design: .monospaced)
    static let smallMonospaced = Font.system(.callout, design: .monospaced)
}
