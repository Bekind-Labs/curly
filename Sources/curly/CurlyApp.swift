import CurlKit
import SwiftUI

@main
struct CurlyApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { commands }
    }

    @CommandsBuilder
    private var commands: some Commands {
        // ⌘V imports a curl command, but hands the paste back to whatever text
        // field is being edited when that is what the user meant.
        CommandGroup(replacing: .pasteboard) {
            Button(L("menu.paste", "Paste")) { model.handlePasteShortcut() }
                .keyboardShortcut("v", modifiers: .command)
            Button(L("menu.copyCommand", "Copy curl Command")) { model.copyCommand() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        CommandGroup(after: .newItem) {
            Menu(L("menu.loadExample", "Load an Example")) {
                ForEach(Examples.all) { example in
                    Button(example.title) { model.load(example) }
                }
            }
            Button(L("menu.startOver", "Start Over")) { model.startOver() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Toggle(L("menu.watchClipboard", "Watch the Clipboard"), isOn: $model.watchesClipboard)
        }
    }
}
