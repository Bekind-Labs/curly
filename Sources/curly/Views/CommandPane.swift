import CurlKit
import SwiftUI

/// The right-hand half: the command as it stands, regenerated on every edit.
/// Read-only on purpose — this is the thing you copy, not the thing you type in.
struct CommandPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView([.vertical, .horizontal]) {
                CommandText(
                    script: model.script,
                    focused: model.focusedRef,
                    flashed: model.flashedRef
                )
                .padding(16)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L("command.title", "The curl command"))
                .font(.headline)
            HelpButton(explanation: .output)
            Spacer()
            Picker("", selection: $model.style) {
                Text(L("command.style.multiLine", "Multi-line")).tag(CurlStyle.multiLine)
                Text(L("command.style.singleLine", "One line")).tag(CurlStyle.singleLine)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                model.copyCommand()
            } label: {
                Label(
                    model.didJustCopy
                        ? L("command.copied", "Copied — now paste it in your terminal")
                        : L("command.copy", "Copy command"),
                    systemImage: model.didJustCopy ? "checkmark.circle.fill" : "doc.on.doc"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .tint(model.didJustCopy ? .green : .accentColor)
            .animation(.easeOut(duration: 0.18), value: model.didJustCopy)

            Button(L("command.startOver", "Start over")) { model.startOver() }
                .controlSize(.large)
        }
        .padding(16)
    }
}

/// The command text, with the tokens belonging to the current field tinted and
/// the tokens that just changed briefly flashed.
struct CommandText: View {
    let script: CurlScript
    let focused: ElementRef?
    let flashed: ElementRef?

    var body: some View {
        Text(highlighted)
            .font(Theme.monospaced)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.15), value: flashed)
    }

    private var highlighted: AttributedString {
        let characters = Array(script.text)
        guard !characters.isEmpty else { return AttributedString() }

        // 0 = plain, 1 = the field you are in, 2 = something that just changed.
        var levels = [UInt8](repeating: 0, count: characters.count)
        func paint(_ ref: ElementRef?, _ level: UInt8) {
            guard let ref else { return }
            for range in script.ranges(for: ref) {
                let lower = max(0, range.lowerBound)
                let upper = min(characters.count, range.upperBound)
                guard lower < upper else { continue }
                for index in lower..<upper where levels[index] < level {
                    levels[index] = level
                }
            }
        }
        paint(focused, 1)
        paint(flashed, 2)

        var result = AttributedString()
        var index = 0
        while index < characters.count {
            var end = index
            while end < characters.count, levels[end] == levels[index] { end += 1 }
            var run = AttributedString(String(characters[index..<end]))
            switch levels[index] {
            case 1: run.backgroundColor = Theme.focusHighlight
            case 2: run.backgroundColor = Theme.changeFlash
            default: break
            }
            result.append(run)
            index = end
        }
        return result
    }
}
