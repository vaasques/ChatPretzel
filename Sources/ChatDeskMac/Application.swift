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
        if result != noErr { main.notice("Global genväg kunde inte registreras (\(result)). Den kan vara upptagen. Välj en annan i Inställningar; inget annat program har ändrats.") }
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
        add(app, "Om ChatPretzel", #selector(about), target: self)
        add(app, "Inställningar…", #selector(settings), ",", target: self)
        app.addItem(.separator())
        add(app, "Göm ChatPretzel", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        add(app, "Göm andra", #selector(NSApplication.hideOtherApplications(_:)), "h", target: NSApp, modifiers: [.command, .option])
        add(app, "Visa alla", #selector(NSApplication.unhideAllApplications(_:)), target: NSApp)
        app.addItem(.separator()); add(app, "Avsluta ChatPretzel", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = submenu("Arkiv")
        add(file, "Ny chatt", #selector(newChat), "n", target: self)
        add(file, "Bifoga originalfiler…", #selector(chooseFiles), "o", target: self)
        add(file, "Spara textutkast lokalt", #selector(saveDraft), "s", target: self, modifiers: [.command, .shift])
        add(file, "Återställ sessionsutkast…", #selector(restoreDraft), target: self)
        add(file, "Spara chatt som bokmärke", #selector(bookmark), "d", target: self)
        file.addItem(.separator()); add(file, "Stäng fönster", #selector(NSWindow.performClose(_:)), "w")
        let edit = submenu("Redigera")
        add(edit, "Ångra", Selector(("undo:")), "z")
        add(edit, "Gör om", Selector(("redo:")), "z", modifiers: [.command, .shift]); edit.addItem(.separator())
        add(edit, "Klipp ut", Selector(("cut:")), "x"); add(edit, "Kopiera", Selector(("copy:")), "c")
        add(edit, "Klistra in", #selector(paste), "v", target: self)
        add(edit, "Markera allt", Selector(("selectAll:")), "a")
        let view = submenu("Visa")
        add(view, "Sök i sidan", #selector(find), "f", target: self)
        add(view, "Ladda om…", #selector(reload), "r", target: self)
        add(view, "Bakåt", #selector(back), "[", target: self); add(view, "Framåt", #selector(forward), "]", target: self)
        view.addItem(.separator())
        add(view, "Zooma in", #selector(zoomIn), "+", target: self)
        add(view, "Zooma ut", #selector(zoomOut), "-", target: self)
        add(view, "Normal zoom", #selector(resetZoom), "0", target: self)
        view.addItem(.separator()); add(view, "Lokalt bibliotek", #selector(library), "l", target: self, modifiers: [.command, .shift])
        add(view, "Bilagornas status", #selector(transfers), target: self)
        add(view, "Nedladdningar", #selector(downloads), target: self)
        let window = submenu("Fönster")
        add(window, "Minimera", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, "Visa ChatPretzel", #selector(showMain), target: self)
        NSApp.windowsMenu = window
        let help = submenu("Hjälp")
        add(help, "Öppna lokalt filtest…", #selector(fixture), target: self)
        add(help, "Exportera teknisk diagnostik…", #selector(diagnostics), target: self)
        add(help, "Viktig teststatus", #selector(testStatus), target: self)
        NSApp.helpMenu = help; NSApp.mainMenu = bar
    }
    @objc private func about() {
        let alert = NSAlert(); alert.messageText = "ChatPretzel 0.1.3 • lokal utvecklingsversion"
        alert.informativeText = "Swift + AppKit + systemets WebKit. Ingen Electron eller separat AI-betalning i appen.\n\nInget officiellt OpenAI-program. Native bygge, inloggning, blandad paste och verklig resursförbrukning måste verifieras på Mac. Se TEST_REPORT.md i källkodspaketet."
        alert.runModal()
    }
    @objc private func testStatus() {
        let alert = NSAlert(); alert.messageText = "Det viktiga testet"
        alert.informativeText = "Markera PDF, DOCX, XLSX, PNG, JPG och TXT i Finder. Cmd+C, fokusera ChatGPTs skrivfält, Cmd+V en gång. Alla sex ska bli riktiga bilagor utan att prompten skickas.\n\nDen lokala testmottagaren kan kontrollera filbytes med SHA-256. Det bevisar inte ChatGPTs uppladdning. Inloggning och tjänstens verkliga beteende testas separat."
        alert.runModal()
    }
    @objc private func fixture() {
        let alert = NSAlert(); alert.messageText = "Byt till lokal testmottagare?"
        alert.informativeText = "Den nuvarande webbsidan lämnas och oskickade bilagor kan försvinna. Testmottagaren gör inga nätverksanrop."
        alert.addButton(withTitle: "Öppna lokalt filtest"); alert.addButton(withTitle: "Avbryt")
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
