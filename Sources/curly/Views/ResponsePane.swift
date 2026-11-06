import AppKit
import CurlKit
import SwiftUI

/// The pane underneath everything else, which appears the first time somebody
/// presses Send and can be closed again.
///
/// How much it shows follows the verbosity setting in the editor, so it always
/// agrees with the command: `-v` shows the whole conversation, `-i` shows the
/// response headers, and otherwise it is just the body.
struct ResponsePane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView([.vertical, .horizontal]) {
                content
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
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
            } else if let response = model.response {
                Button {
                    copyBody(response)
                } label: {
                    Label(L("response.copyBody", "Copy response"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
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

    private func summary(of response: SentResponse) -> String {
        var pieces = [
            String(format: L("response.took", "%d ms"), Int(response.duration * 1000)),
            byteCount(response.body.count),
        ]
        if let type = response.contentType?.split(separator: ";").first {
            pieces.append(String(type))
        }
        return pieces.joined(separator: " · ")
    }

    private func byteCount(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private func copyBody(_ response: SentResponse) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(response.prettyBody, forType: .string)
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        if let error = model.sendError {
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
        } else if let response = model.response {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(response.warnings, id: \.self) { warning in
                    Label(warning.localizedText, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if model.verbosity.showsRequest {
                    transcript(
                        title: L("response.whatWasSent", "What curly sent"),
                        lines: response.requestTranscript,
                        tint: .secondary
                    )
                }

                if model.verbosity.showsResponseHeaders {
                    transcript(
                        title: L("response.whatCameBack", "What came back"),
                        lines: response.responseTranscript,
                        tint: .primary
                    )
                }

                if response.body.isEmpty {
                    Text(L("response.emptyBody", "The answer had no body — just headers."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    if model.verbosity.showsResponseHeaders {
                        Text(L("response.body", "Body"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(response.prettyBody)
                        .font(Theme.smallMonospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func transcript(title: String, lines: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Theme.smallMonospaced)
                    .foregroundStyle(tint)
                    .textSelection(.enabled)
            }
        }
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
