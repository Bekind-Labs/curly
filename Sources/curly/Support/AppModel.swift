import AppKit
import Combine
import CurlKit
import SwiftUI

/// Everything the window knows. One request, one generated command, and a
/// little bookkeeping for the teaching features.
/// Where the clipboard-watching preference is stored. A file-scope constant
/// rather than a static member, because a stored property initialiser cannot
/// refer to `Self`.
private let watchClipboardKey = "watchClipboard"

@MainActor
final class AppModel: ObservableObject {
    /// The request being edited. Always present; `hasImported` says whether the
    /// user has actually put anything in it yet.
    @Published var request = CurlRequest() {
        didSet { if request != oldValue { regenerate() } }
    }
    @Published private(set) var hasImported = false
    @Published var style: CurlStyle = .multiLine { didSet { regenerate() } }
    @Published private(set) var script = CurlScript(text: "curl", segments: [])

    /// The field the cursor is in, whose tokens are highlighted in the command.
    @Published var focusedRef: ElementRef?
    /// The tokens that just changed, flashed briefly so the change is visible.
    @Published private(set) var flashedRef: ElementRef?

    // MARK: Sending

    /// What came back from the last Send, if any. Copying is still the primary
    /// action; this pane only appears once somebody has asked for it.
    @Published var response: SentResponse?
    @Published var sendError: String?
    @Published var isSending = false
    private var sendTask: Task<Void, Never>?

    @Published var importError: String?
    /// Set when the clipboard holds a curl command we have not imported yet.
    @Published var clipboardOffer: String?
    @Published var didJustCopy = false

    /// Watching the clipboard is a preference so it can be turned off; on
    /// macOS reading the general pasteboard does not prompt, so it ships on.
    @Published var watchesClipboard: Bool = UserDefaults.standard
        .object(forKey: watchClipboardKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(watchesClipboard, forKey: watchClipboardKey) }
    }

    private var flashToken = 0
    private var copyToken = 0
    private var lastSeenPasteboardChange = NSPasteboard.general.changeCount

    init() {
        regenerate()
    }

    // MARK: Generated command

    private func regenerate() {
        script = CurlGenerator.script(request, style: style)
    }

    var commandText: String { script.text }

    // MARK: Importing

    /// Reads a curl command. Returns `false` and sets `importError` if it is
    /// not one.
    @discardableResult
    func importCommand(_ text: String) -> Bool {
        do {
            request = try CurlParser.parse(text)
            hasImported = true
            importError = nil
            clipboardOffer = nil
            lastSeenPasteboardChange = NSPasteboard.general.changeCount
            return true
        } catch let error as CurlParserError {
            importError = error.localizedText
            return false
        } catch {
            importError = L("import.error.generic", "That did not look like a curl command.")
            return false
        }
    }

    func load(_ example: Example) {
        importCommand(example.command)
    }

    /// Actually performs the request. The only part of curly that uses the
    /// network, and only ever because the button was pressed.
    func send() {
        guard !isSending else { return }
        sendError = nil

        let plan: RequestPlan
        do {
            plan = try RequestPlanner.plan(for: request)
        } catch {
            sendError = (error as? RequestPlanError)?.localizedText
                ?? L("send.error.generic", "curly could not work out what to send.")
            response = nil
            return
        }

        isSending = true
        sendTask = Task {
            do {
                let result = try await RequestSender.send(plan)
                if !Task.isCancelled {
                    self.response = result
                    self.sendError = nil
                }
            } catch {
                if !Task.isCancelled {
                    self.response = nil
                    self.sendError = (error as? CustomStringConvertible).map(\.description)
                        ?? error.localizedDescription
                }
            }
            self.isSending = false
        }
    }

    func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        isSending = false
    }

    func dismissResponse() {
        cancelSend()
        response = nil
        sendError = nil
    }

    /// True once there is something to show in the pane underneath.
    var showsResponsePane: Bool {
        isSending || response != nil || sendError != nil
    }

    /// How much of the exchange to show, which is the same `-s`/`-i`/`-v`
    /// setting the command carries.
    var verbosity: Verbosity {
        get { request.verbosity }
        set {
            request.verbosity = newValue
            flash(.body)
        }
    }

    func startOver() {
        cancelSend()
        response = nil
        sendError = nil
        request = CurlRequest()
        hasImported = false
        importError = nil
        focusedRef = nil
    }

    // MARK: Clipboard

    var clipboardCommand: String? {
        guard let text = NSPasteboard.general.string(forType: .string) else { return nil }
        return CurlParser.looksLikeCurl(text) ? text : nil
    }

    /// Called when the app comes to the front. Offers an import rather than
    /// doing one, because taking over the window uninvited would be rude.
    func windowBecameActive() {
        guard watchesClipboard else { return }
        let change = NSPasteboard.general.changeCount
        guard change != lastSeenPasteboardChange else { return }
        lastSeenPasteboardChange = change
        clipboardOffer = clipboardCommand
    }

    func acceptClipboardOffer() {
        guard let offer = clipboardOffer else { return }
        importCommand(offer)
    }

    func dismissClipboardOffer() {
        clipboardOffer = nil
    }

    /// ⌘V: import if the clipboard holds a curl command, otherwise let the
    /// ordinary paste happen so text fields keep working.
    func handlePasteShortcut() {
        if isEditingText || clipboardCommand == nil {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            return
        }
        if let command = clipboardCommand {
            importCommand(command)
        }
    }

    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    // MARK: Copying

    func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandText, forType: .string)
        lastSeenPasteboardChange = NSPasteboard.general.changeCount
        copyToken += 1
        let token = copyToken
        didJustCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if self.copyToken == token { self.didJustCopy = false }
        }
    }

    // MARK: Highlighting

    func focus(_ ref: ElementRef?) {
        focusedRef = ref
    }

    /// Flash the tokens belonging to `ref`, so an edit is visible on the right.
    func flash(_ ref: ElementRef) {
        flashToken += 1
        let token = flashToken
        flashedRef = ref
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if self.flashToken == token { self.flashedRef = nil }
        }
    }
}
