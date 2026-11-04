import CurlKit
import SwiftUI

/// The left-hand half: the request, taken apart into things you can poke.
struct RequestEditor: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MethodAndURLSection()
                QuerySection()
                HeadersSection()
                CookiesSection()
                AuthSection()
                BodySection()
                OptionsSection()
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A small round "+" / "−" pair used by every list of rows.
struct RowButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

struct AddRowButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus.circle")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}
