import CurlKit
import SwiftUI

struct MethodAndURLSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var isEnteringCustomMethod = false

    private static let customTag = "\u{1}custom"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            methodCard
            urlCard
        }
    }

    // MARK: Method

    private var methodCard: some View {
        SectionCard(title: L("section.method", "Method"), explanation: .method) {
            HStack(spacing: 10) {
                Picker("", selection: methodSelection) {
                    ForEach(methodChoices, id: \.self) { method in
                        Text(method).tag(method)
                    }
                    Text(L("method.custom", "Something else…")).tag(Self.customTag)
                }
                .labelsHidden()
                .fixedSize()
                .tracksFocus(.method)

                if isEnteringCustomMethod {
                    TrackedField(
                        prompt: L("method.customPrompt", "PURGE"),
                        text: Binding(
                            get: { model.request.method },
                            set: { model.request.method = $0.uppercased() }
                        ),
                        ref: .method
                    )
                    .frame(width: 140)
                }

                if model.request.explicitMethod == nil {
                    Text(L("method.implied", "curl works this out on its own"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var methodChoices: [String] {
        var choices = CurlRequest.commonMethods
        let current = model.request.method
        if !choices.contains(current) { choices.append(current) }
        return choices
    }

    private var methodSelection: Binding<String> {
        Binding(
            get: { isEnteringCustomMethod ? Self.customTag : model.request.method },
            set: { newValue in
                if newValue == Self.customTag {
                    isEnteringCustomMethod = true
                } else {
                    isEnteringCustomMethod = false
                    model.request.method = newValue
                    model.flash(.method)
                }
            }
        )
    }

    // MARK: URL

    private var urlCard: some View {
        SectionCard(title: L("section.url", "Web address"), explanation: .url) {
            VStack(alignment: .leading, spacing: 10) {
                TrackedField(
                    prompt: L("url.whole", "https://api.example.com/v1/items"),
                    text: $model.request.url.text,
                    ref: .url
                )

                HStack(alignment: .bottom, spacing: 8) {
                    labelled(L("url.scheme", "Scheme"), width: 86) {
                        TrackedField(prompt: "https", text: $model.request.url.scheme, ref: .urlScheme)
                    }
                    labelled(L("url.host", "Host"), width: nil) {
                        TrackedField(prompt: "api.example.com", text: $model.request.url.host, ref: .urlHost)
                    }
                    labelled(L("url.port", "Port"), width: 72) {
                        TrackedField(
                            prompt: L("url.portPrompt", "none"),
                            text: Binding(
                                get: { model.request.url.port ?? "" },
                                set: { model.request.url.port = $0.isEmpty ? nil : $0 }
                            ),
                            ref: .urlPort
                        )
                    }
                }

                labelled(L("url.path", "Path"), width: nil) {
                    TrackedField(prompt: "/v1/items", text: $model.request.url.path, ref: .urlPath)
                }

                Toggle(
                    L("url.useURLFlag", "Write the address with --url"),
                    isOn: $model.request.url.usesURLFlag
                )
                .font(.caption)
                .tracksFocus(.url)
            }
        }
    }

    private func labelled<Content: View>(
        _ title: String,
        width: CGFloat?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(width: width)
    }
}
