import AppKit
import Combine
import CurlKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.clipboardOffer != nil {
                ClipboardBanner()
                Divider()
            }
            if model.hasImported {
                HSplitView {
                    RequestEditor()
                        .frame(minWidth: 420, idealWidth: 620)
                    CommandPane()
                        .frame(minWidth: 340, idealWidth: 520)
                }
            } else {
                ImportView()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            model.windowBecameActive()
        }
    }
}

/// The non-modal nudge when the clipboard holds a curl command.
struct ClipboardBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.tint)
            Text(L("banner.clipboard", "Looks like you copied a curl command — import it?"))
                .font(.callout)
            Spacer()
            Button(L("banner.import", "Import")) { model.acceptClipboardOffer() }
                .buttonStyle(.borderedProminent)
            Button(L("banner.notNow", "Not now")) { model.dismissClipboardOffer() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.12))
    }
}
