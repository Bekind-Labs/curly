import CurlKit
import SwiftUI
import UniformTypeIdentifiers

/// What you see on launch: somewhere obvious to put a curl command.
struct ImportView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(L("import.title", "Paste a curl command"))
                .font(.largeTitle.weight(.semibold))
            Text(L(
                "import.subtitle",
                "In your browser’s developer tools, right-click a request and choose “Copy as cURL”. Then press ⌘V here."
            ))
            .font(.title3)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 560)

            pasteTarget

            if let error = model.importError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            examples
            Spacer()
            Text(L("import.footer", "curly never sends anything. Your terminal does that bit."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.utf8PlainText, .plainText], isTargeted: $isTargeted) { providers in
            loadDrop(providers)
        }
    }

    private var pasteTarget: some View {
        Button {
            model.handlePasteShortcut()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.tint)
                Text(L("import.dropTarget", "Paste here  ⌘V"))
                    .font(.title3.weight(.medium))
                Text(L("import.dropHint", "…or drop a command in"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 440, height: 190)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                        style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: [8, 6])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var examples: some View {
        VStack(spacing: 8) {
            Text(L("import.noDevtools", "No developer tools to hand?"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Menu(L("import.loadExample", "Load an example")) {
                ForEach(Examples.all) { example in
                    Button {
                        model.load(example)
                    } label: {
                        Text(example.title)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func loadDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadDataRepresentation(forTypeIdentifier: "public.utf8-plain-text") { data, _ in
            guard let data, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in model.importCommand(text) }
        }
        return true
    }
}
