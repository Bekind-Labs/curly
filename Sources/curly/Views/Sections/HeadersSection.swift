import CurlKit
import SwiftUI

struct HeadersSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionCard(
            title: L("section.headers", "Headers"),
            explanation: .headers,
            subtitle: L("headers.hint", "Switch one off to see what the site does without it — nothing is lost.")
        ) {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                ForEach($model.request.headers) { $header in
                    HeaderRow(header: $header, remove: { remove(header.id) })
                }
                if model.request.headers.isEmpty {
                    Text(L("headers.empty", "No headers yet."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                AddRowButton(title: L("headers.add", "Add a header")) {
                    model.request.headers.append(Header(name: "", value: ""))
                }
            }
        }
    }

    private func remove(_ id: UUID) {
        model.request.headers.removeAll { $0.id == id }
    }
}

private struct HeaderRow: View {
    @Binding var header: Header
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: $header.isEnabled)
                .labelsHidden()
                .help(L("row.toggle", "Include this in the request"))
            TrackedField(
                prompt: L("headers.name", "Name"),
                text: $header.name,
                ref: .header(header.id)
            )
            .frame(width: 170)
            Text(":").foregroundStyle(.secondary)
            TrackedField(
                prompt: L("headers.value", "Value"),
                text: $header.value,
                ref: .header(header.id)
            )
            RowButton(systemImage: "minus.circle", help: L("row.remove", "Remove this row"), action: remove)
        }
        .opacity(header.isEnabled ? 1 : 0.45)
    }
}
