import CurlKit
import SwiftUI

/// How much of the exchange to show. It writes curl's own output flags
/// (`-s`, `-i`, `-v`) into the command, and the response pane underneath
/// follows the same setting — so what you asked to see and what you get are
/// never two different things.
struct VerbositySection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionCard(
            title: L("section.verbosity", "How much to show"),
            explanation: .verbosity,
            subtitle: note
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $model.verbosity) {
                    Text(L("verbosity.quiet", "Quiet")).tag(Verbosity.quiet)
                    Text(L("verbosity.normal", "Just the answer")).tag(Verbosity.normal)
                    Text(L("verbosity.headers", "Answer + headers")).tag(Verbosity.headers)
                    Text(L("verbosity.verbose", "Everything")).tag(Verbosity.verbose)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tracksFocus(flagRef)
            }
        }
    }

    /// Highlight the flag this setting writes, when it writes one.
    private var flagRef: ElementRef {
        guard
            let flag = model.verbosity.flag,
            let option = model.request.option(flag)
        else { return .command }
        return .option(option.id)
    }

    private var note: String? {
        switch model.verbosity {
        case .quiet:
            return L("verbosity.note.quiet", "-s — curl keeps its progress meter and errors to itself.")
        case .normal:
            return L("verbosity.note.normal", "No flag needed: curl prints what came back and nothing else.")
        case .headers:
            return L("verbosity.note.headers", "-i — the response headers are printed above the body.")
        case .verbose:
            return L("verbosity.note.verbose", "-v — the whole conversation, including what was sent.")
        }
    }
}
