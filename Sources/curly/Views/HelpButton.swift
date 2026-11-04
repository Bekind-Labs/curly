import CurlKit
import SwiftUI

/// The small "?" that every section carries. Tapping it pops over one to three
/// sentences of plain English — no modal, no menu diving.
struct HelpButton: View {
    let explanation: Explanation
    @State var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(L("help.button", "What is this?"))
        .accessibilityLabel(Text(L("help.button", "What is this?")))
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(localizedTitle)
                    .font(.headline)
                Text(localizedText)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 320)
        }
    }

    private var localizedTitle: String {
        L(explanation.key + ".title", explanation.title)
    }

    private var localizedText: String {
        L(explanation.key, explanation.text)
    }
}
