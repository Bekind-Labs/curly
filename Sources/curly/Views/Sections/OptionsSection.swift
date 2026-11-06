import CurlKit
import SwiftUI

/// Flags without a section of their own. Each is a toggle with one line of
/// English next to it, including the ones curly has never heard of.
struct OptionsSection: View {
    @EnvironmentObject private var model: AppModel

    private static let suggested = ["--compressed", "--location", "--insecure", "--head", "--silent", "--verbose"]

    var body: some View {
        SectionCard(
            title: L("section.options", "Other options"),
            explanation: .otherOptions,
            subtitle: model.request.options.isEmpty
                ? L("options.empty", "No extra curl options are set.")
                : nil
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach($model.request.options) { $option in
                    OptionRow(option: $option) {
                        model.request.options.removeAll { $0.id == option.id }
                        model.flash(.option(option.id))
                    }
                }
                addMenu
            }
        }
    }

    private var addMenu: some View {
        Menu(L("options.add", "Add an option")) {
            ForEach(Self.suggested, id: \.self) { flag in
                if model.request.option(flag) == nil, let spec = CurlOptionCatalog.spec(forFlag: flag) {
                    Button("\(spec.long) — \(L("option." + spec.long, spec.explanation))") {
                        model.request.options.append(CurlOption(flag: spec.long))
                        model.flash(.body)
                    }
                }
            }
            Divider()
            Button(L("options.addOther", "Something else…")) {
                model.request.options.append(CurlOption(flag: "--"))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.callout)
    }
}

private struct OptionRow: View {
    @Binding var option: CurlOption
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Toggle("", isOn: $option.isEnabled)
                    .labelsHidden()
                    .help(L("row.toggle", "Include this in the request"))
                TrackedField(prompt: "--flag", text: $option.flag, ref: .option(option.id))
                    .frame(width: 170)
                if option.value != nil {
                    TrackedField(
                        prompt: L("options.value", "value"),
                        text: Binding(
                            get: { option.value ?? "" },
                            set: { option.value = $0 }
                        ),
                        ref: .option(option.id)
                    )
                } else {
                    Spacer()
                }
                RowButton(systemImage: "minus.circle", help: L("row.remove", "Remove this row"), action: remove)
            }
            Text(explanation)
                .font(.caption)
                .foregroundStyle(option.isUnrecognised ? .orange : .secondary)
                .padding(.leading, 30)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(option.isEnabled ? 1 : 0.45)
    }

    private var explanation: String {
        if let spec = option.spec {
            return L("option." + spec.long, spec.explanation)
        }
        return L("options.unknown", "curly does not know this flag, so it is passed along exactly as written.")
    }
}
