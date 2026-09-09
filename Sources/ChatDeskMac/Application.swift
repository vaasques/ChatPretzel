import AppKit
import Carbon

@MainActor
public enum ChatDeskApplication {
    private static var retainedDelegate: AppDelegate?
    public static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate(); retainedDelegate = delegate; app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences()
    private var main: MainWindowController!
    private let hotKey = GlobalHotKey()
    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenu()
        let arguments = Set(CommandLine.arguments)
        main = MainWindowController(preferences: preferences, fixture: arguments.contains("--fixture"), safeMode: arguments.contains("--safe-mode"))
        main.onPreferencesChanged = { [weak self] in self?.registerHotKey() }
        hotKey.onPress = { [weak self] in self?.main.showAndFocus() }; registerHotKey()
        main.showAndFocus()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { main.showAndFocus(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard main?.prepareToQuit() != false else { return .terminateCancel }
        hotKey.unregister(); return .terminateNow
    }
    private func registerHotKey() {
        hotKey.unregister()
        guard preferences.globalHotKey else { return }
        let result = hotKey.register(useCommand: preferences.hotKeyUsesCommand)
        if result != noErr { main.notice("The global shortcut could not be registered (\(result)). It may already be in use. Choose another shortcut in Settings; no other app was changed.") }
    }
    private func makeMenu() {
        let bar = NSMenu()
        func submenu(_ name: String) -> NSMenu {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: ""); bar.addItem(item)
            let menu = NSMenu(title: name); item.submenu = menu; return menu
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil,
                 modifiers: NSEvent.ModifierFlags = [.command]) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target; item.keyEquivalentModifierMask = modifiers; menu.addItem(item)
        }
        let app = submenu("ChatPretzel")
        add(app, "About ChatPretzel", #selector(about), target: self)
        add(app, "Settings…", #selector(settings), ",", target: self)
        app.addItem(.separator())
        add(app, "Hide ChatPretzel", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", target: NSApp, modifiers: [.command, .option])
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)), target: NSApp)
        app.addItem(.separator()); add(app, "Quit ChatPretzel", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = submenu("File")
        add(file, "New Chat", #selector(newChat), "n", target: self)
        add(file, "Attach Original Files…", #selector(chooseFiles), "o", target: self)
        add(file, "Save Text Draft Locally", #selector(saveDraft), "s", target: self, modifiers: [.command, .shift])
        add(file, "Restore Session Draft…", #selector(restoreDraft), target: self)
        add(file, "Bookmark Chat", #selector(bookmark), "d", target: self)
        file.addItem(.separator()); add(file, "Close Window", #selector(NSWindow.performClose(_:)), "w")
        let edit = submenu("Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        add(edit, "Redo", Selector(("redo:")), "z", modifiers: [.command, .shift]); edit.addItem(.separator())
        add(edit, "Cut", Selector(("cut:")), "x"); add(edit, "Copy", Selector(("copy:")), "c")
        add(edit, "Paste", #selector(paste), "v", target: self)
        add(edit, "Select All", Selector(("selectAll:")), "a")
        let view = submenu("View")
        add(view, "Find on Page", #selector(find), "f", target: self)
        add(view, "Reload…", #selector(reload), "r", target: self)
        add(view, "Back", #selector(back), "[", target: self); add(view, "Forward", #selector(forward), "]", target: self)
        view.addItem(.separator())
        add(view, "Zoom In", #selector(zoomIn), "+", target: self)
        add(view, "Zoom Out", #selector(zoomOut), "-", target: self)
        add(view, "Actual Size", #selector(resetZoom), "0", target: self)
        view.addItem(.separator()); add(view, "Local Library", #selector(library), "l", target: self, modifiers: [.command, .shift])
        add(view, "Attachment Status", #selector(transfers), target: self)
        add(view, "Downloads", #selector(downloads), target: self)
        let window = submenu("Window")
        add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, "Show ChatPretzel", #selector(showMain), target: self)
        NSApp.windowsMenu = window
        let help = submenu("Help")
        add(help, "Open Local File Test…", #selector(fixture), target: self)
        add(help, "Export Technical Diagnostics…", #selector(diagnostics), target: self)
        add(help, "Important Test Status", #selector(testStatus), target: self)
        NSApp.helpMenu = help; NSApp.mainMenu = bar
    }
    @objc private func about() {
        let alert = NSAlert(); alert.messageText = "ChatPretzel 0.2.0"
        alert.informativeText = "Built with Swift, AppKit, and the WebKit engine included with macOS. No Electron and no separate AI subscription inside the app. Microphone access is requested only when you start voice input in ChatGPT; camera access remains blocked.\n\nChatPretzel is an independent, unofficial project. It is not affiliated with, endorsed by, or sponsored by OpenAI. Sign in with your ChatGPT password rather than a passkey."
        alert.runModal()
    }
    @objc private func testStatus() {
        let alert = NSAlert(); alert.messageText = "Important attachment test"
        alert.informativeText = "Select PDF, DOCX, XLSX, PNG, JPG, and TXT files in Finder. Press Command+C, focus ChatGPT's message field, and press Command+V once. You can also copy attachments in Mail and paste them into the message field. The files should become real attachments without sending the prompt.\n\nThe local test receiver can verify file bytes with SHA-256. It does not prove that ChatGPT's server accepted an upload. Login and live service behavior are tested separately."
        alert.runModal()
    }
    @objc private func fixture() {
        let alert = NSAlert(); alert.messageText = "Switch to the local test receiver?"
        alert.informativeText = "This leaves the current web page, and unsent attachments may disappear. The test receiver makes no network requests."
        alert.addButton(withTitle: "Open Local File Test"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { main.openFixture() }
    }
    @objc private func diagnostics() { main.exportDiagnostics() }
    @objc private func newChat() { main.newChat() }
    @objc private func chooseFiles() { main.chooseFiles() }
    @objc private func saveDraft() { main.saveCurrentDraft() }
    @objc private func restoreDraft() { main.restoreSessionDraft() }
    @objc private func bookmark() { main.addBookmark() }
    @objc private func settings() { main.showSettings() }
    @objc private func paste() { main.pasteFromMenu() }
    @objc private func reload() { main.reload() }
    @objc private func back() { main.back() }
    @objc private func forward() { main.forward() }
    @objc private func find() { main.showSearch() }
    @objc private func zoomIn() { main.changeZoom(0.1) }
    @objc private func zoomOut() { main.changeZoom(-0.1) }
    @objc private func resetZoom() { main.resetZoom() }
    @objc private func library() { main.showLibrary() }
    @objc private func transfers() { main.showTransfers() }
    @objc private func downloads() { main.showDownloads() }
    @objc private func showMain() { main.showAndFocus() }
}
