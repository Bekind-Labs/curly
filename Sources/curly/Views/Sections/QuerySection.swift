import CurlKit
import SwiftUI

/// The bit of the address after the "?", as rows you can edit and switch off.
struct QuerySection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionCard(
            title: L("section.query", "Query string"),
            explanation: .query,
            subtitle: model.request.url.query.isEmpty
                ? L("query.empty", "This address has nothing after the “?” yet.")
                : nil
        ) {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                ForEach($model.request.url.query) { $item in
                    QueryRow(item: $item, remove: { remove(item.id) })
                }
                AddRowButton(title: L("query.add", "Add a query parameter")) {
                    model.request.url.query.append(QueryItem(name: "", value: ""))
                }
            }
        }
    }

    private func remove(_ id: UUID) {
        model.request.url.query.removeAll { $0.id == id }
    }
}

private struct QueryRow: View {
    @Binding var item: QueryItem
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: $item.isEnabled)
                .labelsHidden()
                .help(L("row.toggle", "Include this in the request"))
            TrackedField(
                prompt: L("query.name", "name"),
                text: $item.name,
                ref: .queryItem(item.id)
            )
            Text("=").foregroundStyle(.secondary)
            TrackedField(
                prompt: L("query.value", "value"),
                text: decodedValue,
                ref: .queryItem(item.id)
            )
            RowButton(systemImage: "minus.circle", help: L("row.remove", "Remove this row"), action: remove)
        }
        .opacity(item.isEnabled ? 1 : 0.45)
    }

    /// The editor shows `swift ui`; the address keeps `swift%20ui`.
    private var decodedValue: Binding<String> {
        Binding(
            get: { URLParts.decode(item.value ?? "") },
            set: { item.value = URLParts.encode($0) }
        )
    }
}
