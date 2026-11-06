import AppKit
import SwiftUI

/// A plain-text editor that is genuinely plain.
///
/// SwiftUI's `TextEditor` is backed by an `NSTextView` that inherits macOS's
/// automatic substitutions, so typing `"` into a JSON body gets you `“` and
/// the body stops being JSON. There is no SwiftUI modifier for that, so the
/// text view is made here and told to leave the text alone.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator

        // The whole point of this type.
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticPeriodSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.font = font
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.drawsBackground = false
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.font = font
        guard textView.string != text else { return }

        // The text changed from outside — laid out as JSON, say. Keep the
        // cursor where it was if that position still exists.
        let length = (text as NSString).length
        let kept = textView.selectedRanges.compactMap { value -> NSValue? in
            let range = value.rangeValue
            guard range.location <= length else { return nil }
            return NSValue(range: NSRange(
                location: range.location,
                length: min(range.length, length - range.location)
            ))
        }
        textView.string = text
        if !kept.isEmpty { textView.selectedRanges = kept }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor

        init(_ parent: PlainTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }
    }
}
