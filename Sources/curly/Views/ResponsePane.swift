import AppKit
import CurlKit
import SwiftUI

/// Which part of the exchange the pane is showing.
enum ResponseTab: String, CaseIterable, Identifiable {
    case body
    case headers
    case sent

    var id: String { rawValue }
}

/// The pane underneath everything else, which appears the first time somebody
/// presses Send and can be closed again.
///
/// Everything that came back is here and always reachable — the body, the
/// response headers, and what curly sent. The verbosity setting in the editor
/// decides what the *command* would print in a terminal, which is a different
/// question, so the pane says which flag to add rather than hiding anything.
struct ResponsePane: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: ResponseTab = .body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.response != nil {
                tabStrip
            }
            Divider()
            ScrollView([.vertical, .horizontal]) {
                content
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: model.response) { _, response in
            guard let response else { return }
            tab = response.body.isEmpty ? .headers : .body
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            if model.isSending {
                ProgressView()
                    .controlSize(.small)
                Text(L("response.sending", "Sending…"))
                    .font(.headline)
            } else if let response = model.response {
                StatusBadge(response: response)
                Text(summary(of: response))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if model.sendError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(L("response.failed", "The request did not go through"))
                    .font(.headline)
            }

            Spacer()

            if model.isSending {
                Button(L("response.cancel", "Cancel")) { model.cancelSend() }
            } else if model.response != nil {
                Button {
                    copyCurrentTab()
                } label: {
                    Label(L("response.copy", "Copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(L("response.copyHelp", "Copy whatever this tab is showing"))
            }

            Button {
                model.dismissResponse()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("response.close", "Close this pane"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var tabStrip: some View {
        Picker("", selection: $tab) {
            Text(L("response.tab.body", "Body")).tag(ResponseTab.body)
            Text(headersTabTitle).tag(ResponseTab.headers)
            Text(L("response.tab.sent", "What was sent")).tag(ResponseTab.sent)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var headersTabTitle: String {
        let count = model.response?.headers.count ?? 0
        return String(format: L("response.tab.headers", "Headers (%d)"), count)
    }

    private func summary(of response: SentResponse) -> String {
        var pieces = [
            String(format: L("response.took", "%d ms"), Int(response.duration * 1000)),
            ByteCountFormatter.string(fromByteCount: Int64(response.body.count), countStyle: .file),
        ]
        if let type = response.contentType?.split(separator: ";").first {
            pieces.append(String(type))
        }
        return pieces.joined(separator: " · ")
    }

    private func copyCurrentTab() {
        guard let response = model.response else { return }
        let text: String
        switch tab {
        case .body: text = response.prettyBody
        case .headers: text = response.headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
        case .sent: text = response.requestTranscript.joined(separator: "\n")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let error = model.sendError {
            failure(error)
        } else if let response = model.response {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(response.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if !response.unsupportedOptions.isEmpty {
                    Label(
                        String(
                            format: L(
                                "response.unsupported",
                                "curly sent this itself and cannot do %@. Copy the command and run it in your terminal if those matter here."
                            ),
                            response.unsupportedOptions.joined(separator: ", ")
                        ),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }

                switch tab {
                case .body: bodyTab(response)
                case .headers: headersTab(response)
                case .sent: sentTab(response)
                }
            }
        }
    }

    private func failure(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(L(
                "response.errorHint",
                "The command itself is still fine — copy it and try it in your terminal to compare."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func bodyTab(_ response: SentResponse) -> some View {
        if response.body.isEmpty {
            Text(L("response.emptyBody", "The answer had no body — just headers."))
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text(response.prettyBody)
                .font(Theme.smallMonospaced)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headersTab(_ response: SentResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(response.responseTranscript.first ?? "")
                .font(Theme.smallMonospaced)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(response.headers.enumerated()), id: \.offset) { _, field in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(field.name + ":")
                            .font(Theme.smallMonospaced.weight(.semibold))
                            .frame(minWidth: 160, alignment: .leading)
                        Text(field.value)
                            .font(Theme.smallMonospaced)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !model.verbosity.showsResponseHeaders {
                terminalHint(
                    L(
                        "response.hint.headers",
                        "Your command would not print these in a terminal. Add -i and it will."
                    ),
                    flag: "-i",
                    verbosity: .headers
                )
            }
        }
    }

    private func sentTab(_ response: SentResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(response.requestTranscript.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(Theme.smallMonospaced)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if !model.verbosity.showsRequest {
                terminalHint(
                    L(
                        "response.hint.sent",
                        "Your command would not print this in a terminal. Add -v and it will."
                    ),
                    flag: "-v",
                    verbosity: .verbose
                )
            }
        }
    }

    /// The pane shows everything that came back; this says what to add to the
    /// command so the terminal shows it too.
    private func terminalHint(_ message: String, flag: String, verbosity: Verbosity) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(format: L("response.hint.add", "Add %@"), flag)) {
                model.verbosity = verbosity
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Spacer()
        }
        .padding(.top, 4)
    }
}

/// The coloured status code at the top of the pane.
struct StatusBadge: View {
    let response: SentResponse

    var body: some View {
        Text("\(response.statusCode) \(response.statusText)")
            .font(.headline.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint)
            )
    }

    private var tint: Color {
        if response.isSuccess { return .green }
        if response.isRedirect { return .blue }
        if response.isError { return .red }
        return .gray
    }
}
