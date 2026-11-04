import CurlKit
import SwiftUI

/// A text field that tells the app which part of the command it belongs to, so
/// that putting the cursor in it lights up the matching tokens on the right —
/// and so that typing in it makes those tokens flash.
struct TrackedField: View {
    let prompt: String
    @Binding var text: String
    let ref: ElementRef
    var monospaced = true

    @EnvironmentObject var model: AppModel
    @FocusState var isFocused: Bool

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(monospaced ? Theme.smallMonospaced : nil)
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    model.focus(ref)
                } else if model.focusedRef == ref {
                    model.focus(nil)
                }
            }
            .onChange(of: text) { _, _ in
                model.flash(ref)
            }
            .onHover { inside in
                if inside, !isFocused { model.focus(ref) }
            }
    }
}

/// Highlights whatever it wraps when pointed at, for controls that are not
/// text fields (pickers, toggles).
struct TracksFocus: ViewModifier {
    let ref: ElementRef
    @EnvironmentObject var model: AppModel

    func body(content: Content) -> some View {
        content.onHover { inside in
            model.focus(inside ? ref : nil)
        }
    }
}

extension View {
    func tracksFocus(_ ref: ElementRef) -> some View {
        modifier(TracksFocus(ref: ref))
    }
}
