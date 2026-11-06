import CurlKit
import SwiftUI

struct BodySection: View {
    @EnvironmentObject var model: AppModel

    private static let commonTypes = [
        "application/json",
        "application/x-www-form-urlencoded",
        "text/plain",
        "text/xml",
        "multipart/form-data",
    ]

    var body: some View {
        SectionCard(
            title: L("section.body", "Body"),
            explanation: .body,
            subtitle: shapeNote
        ) {
            VStack(alignment: .leading, spacing: 10) {
                contentTypeRow
                switch model.request.bodyShape {
                case .empty:
                    emptyBody
                case .multipart, .urlEncodedFields, .mixed:
                    bodyPartRows
                case .formURLEncoded:
                    formFieldRows
                case .text:
                    textBody
                }
            }
        }
    }

    // MARK: Content type

    private var contentTypeRow: some View {
        HStack(spacing: 8) {
            Text(L("body.contentType", "Content-Type"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HelpButton(explanation: .contentType)
            Picker("", selection: contentTypeSelection) {
                Text(L("body.contentType.none", "not set")).tag("")
                ForEach(Self.commonTypes, id: \.self) { type in
                    Text(type).tag(type)
                }
                if let current = model.request.contentTypeBase,
                   !Self.commonTypes.contains(current) {
                    Text(current).tag(current)
                }
            }
            .labelsHidden()
            .fixedSize()
            .font(.caption)
            .tracksFocus(.body)
            Spacer()
        }
    }

    /// Changing the type here changes the header, and nothing else — the body
    /// text is left alone, because guessing at a conversion would be worse.
    private var contentTypeSelection: Binding<String> {
        Binding(
            get: { model.request.contentTypeBase ?? "" },
            set: { newValue in
                model.request.setContentType(newValue.isEmpty ? nil : newValue)
                model.flash(.body)
            }
        )
    }

    // MARK: Shapes

    private var emptyBody: some View {
        HStack {
            Text(L("body.empty", "This request sends nothing in its body."))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            AddRowButton(title: L("body.add", "Add a body")) {
                model.request.bodyParts = [BodyPart(kind: .dataRaw, value: "")]
                model.flash(.body)
            }
        }
    }

    private var textBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackedEditor(
                text: Binding(
                    get: { model.request.bodyText },
                    set: { model.request.setBodyText($0) }
                ),
                ref: .body
            )
            .frame(minHeight: 120, maxHeight: 260)

            if SmartQuotes.arePresent(in: model.request.bodyText) {
                smartQuoteWarning
            }

            if isJSONish {
                jsonControls
            }
        }
    }

    /// Pasted text can arrive with curly quotes already in it, from a document
    /// or a chat window. curly will not quietly rewrite what you pasted, but
    /// it will point at it and offer.
    private var smartQuoteWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.bubble")
                .foregroundStyle(.orange)
            Text(
                SmartQuotes.straighteningWouldFixJSON(model.request.bodyText)
                    ? L("body.smartQuotes.breaksJSON", "There are curly quotes in here, which is why this is not valid JSON.")
                    : L("body.smartQuotes.present", "There are curly quotes in here. Servers rarely want those.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(L("body.smartQuotes.fix", "Straighten them")) {
                model.request.setBodyText(SmartQuotes.straighten(model.request.bodyText))
                model.flash(.body)
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }

    private var jsonControls: some View {
        HStack(spacing: 10) {
            Button(L("body.prettyPrint", "Lay it out")) {
                if let pretty = JSONFormatter.prettyPrinted(model.request.bodyText) {
                    model.request.setBodyText(pretty)
                    model.flash(.body)
                }
            }
            Button(L("body.minify", "Squash it back")) {
                if let compact = JSONFormatter.minified(model.request.bodyText) {
                    model.request.setBodyText(compact)
                    model.flash(.body)
                }
            }
            HelpButton(explanation: .json)
            Spacer()
            if let complaint = JSONFormatter.validate(model.request.bodyText) {
                Label(complaint, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                Label(L("body.jsonOK", "Valid JSON"), systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }

    private var isJSONish: Bool {
        model.request.contentTypeBase?.contains("json") == true
            || model.request.bodyIsJSON
    }

    private var formFieldRows: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            HStack(spacing: 6) {
                Text(L("body.formFields", "Form fields"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HelpButton(explanation: .formBody)
            }
            ForEach(Array(model.request.formFields.enumerated()), id: \.offset) { index, field in
                HStack(spacing: 6) {
                    TrackedField(prompt: L("body.fieldName", "name"), text: fieldBinding(index, \.name), ref: .body)
                        .frame(width: 170)
                    Text("=").foregroundStyle(.secondary)
                    TrackedField(prompt: L("body.fieldValue", "value"), text: fieldBinding(index, \.value), ref: .body)
                    RowButton(systemImage: "minus.circle", help: L("row.remove", "Remove this row")) {
                        var fields = model.request.formFields
                        guard fields.indices.contains(index) else { return }
                        fields.remove(at: index)
                        model.request.setFormFields(fields)
                        model.flash(.body)
                    }
                }
                .id(field.id)
            }
            AddRowButton(title: L("body.addField", "Add a form field")) {
                var fields = model.request.formFields
                fields.append(FormField(name: "", value: ""))
                model.request.setFormFields(fields)
                model.flash(.body)
            }
            Text(model.request.bodyText.isEmpty ? " " : model.request.bodyText)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func fieldBinding(_ index: Int, _ keyPath: WritableKeyPath<FormField, String>) -> Binding<String> {
        Binding(
            get: {
                let fields = model.request.formFields
                return fields.indices.contains(index) ? fields[index][keyPath: keyPath] : ""
            },
            set: { newValue in
                var fields = model.request.formFields
                guard fields.indices.contains(index) else { return }
                fields[index][keyPath: keyPath] = newValue
                model.request.setFormFields(fields)
            }
        )
    }

    /// Multipart fields, --data-urlencode pieces and anything mixed: one row
    /// per argument, keeping the flag each was written with.
    private var bodyPartRows: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            ForEach($model.request.bodyParts) { $part in
                HStack(spacing: 6) {
                    Toggle("", isOn: $part.isEnabled)
                        .labelsHidden()
                        .help(L("row.toggle", "Include this in the request"))
                    Text(part.spelling)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 128, alignment: .leading)
                    TrackedField(
                        prompt: L("body.partValue", "name=value"),
                        text: $part.value,
                        ref: .bodyPart(part.id)
                    )
                    RowButton(systemImage: "minus.circle", help: L("row.remove", "Remove this row")) {
                        model.request.bodyParts.removeAll { $0.id == part.id }
                        model.flash(.body)
                    }
                }
                .opacity(part.isEnabled ? 1 : 0.45)
            }
            if model.request.bodyShape == .multipart {
                Text(L("body.multipartHint", "A value starting with @ is a file to upload."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shapeNote: String? {
        switch model.request.bodyShape {
        case .multipart:
            return L("body.note.multipart", "Sent as a form that can carry files.")
        case .urlEncodedFields:
            return L("body.note.urlencoded", "Each piece is escaped by curl before it is sent.")
        case .mixed:
            return L("body.note.mixed", "This body is built from several different flags.")
        default:
            return nil
        }
    }
}

/// A multi-line editor that reports focus and flashes on change, like
/// `TrackedField` does for one-liners — and that never rewrites what you type.
struct TrackedEditor: View {
    @Binding var text: String
    let ref: ElementRef

    @EnvironmentObject var model: AppModel

    var body: some View {
        PlainTextEditor(text: $text) { isEditing in
            if isEditing {
                model.focus(ref)
            } else if model.focusedRef == ref {
                model.focus(nil)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onChange(of: text) { _, _ in
            model.flash(ref)
        }
    }
}
