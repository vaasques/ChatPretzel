import AppKit

@MainActor
final class SettingsPanel: NSWindowController {
    let preferences: Preferences
    let safe = NSButton(checkboxWithTitle: "Felsäkert läge: inga egna webbskript", target: nil, action: nil)
    let paste = NSButton(checkboxWithTitle: "Assisterad filinklistrning via WebKits filkontroll (ej live-verifierad)", target: nil, action: nil)
    let cv = NSButton(checkboxWithTitle: "Control+C/Control+V inne i appen", target: nil, action: nil)
    let hotKey = NSButton(checkboxWithTitle: "Global genväg visar samma fönster", target: nil, action: nil)
    let shortcut = NSPopUpButton()
    let width = NSPopUpButton()
    var onApply: (() -> Void)?
    init(preferences: Preferences) {
        self.preferences = preferences
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 630, height: 365),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "ChatPretzel-inställningar"; panel.isReleasedWhenClosed = false
        super.init(window: panel)
        safe.state = preferences.safeMode ? .on : .off; paste.state = preferences.assistedPaste ? .on : .off
        cv.state = preferences.controlCV ? .on : .off; hotKey.state = preferences.globalHotKey ? .on : .off
        shortcut.addItems(withTitles: ["Control + Option + Space", "Command + Option + Space"])
        shortcut.selectItem(at: preferences.hotKeyUsesCommand ? 1 : 0)
        width.addItems(withTitles: ["Webbens ordinarie läsbredd", "880 px", "1040 px", "1280 px"])
        width.selectItem(at: [0, 880, 1040, 1280].firstIndex(of: preferences.readingWidth) ?? 0)
        let info = NSTextField(wrappingLabelWithString: "Ändringar laddar om sidan. Befintliga webb-bilagor kan behöva väljas igen. Kontot och det lokala biblioteket raderas inte. Avstängd filassistans testar WebKits ordinarie paste utan automatisk fallback.")
        info.textColor = .secondaryLabelColor
        let button = NSButton(title: "Spara och ladda om…", target: self, action: #selector(apply))
        installPanelContent(panel, views: [safe, paste, cv, hotKey, shortcut, width, info, button], flexible: info)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func apply() {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = "Ladda om ChatGPT?"
        alert.informativeText = "Kopiera viktig oskickad text först. Uppladdade men oskickade bilagor kan gå förlorade vid omladdning."
        alert.addButton(withTitle: "Spara och ladda om"); alert.addButton(withTitle: "Avbryt")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.preferences.safeMode = self.safe.state == .on; self.preferences.assistedPaste = self.paste.state == .on
            self.preferences.controlCV = self.cv.state == .on; self.preferences.globalHotKey = self.hotKey.state == .on
            self.preferences.hotKeyUsesCommand = self.shortcut.indexOfSelectedItem == 1
            self.preferences.readingWidth = [0, 880, 1040, 1280][max(0, self.width.indexOfSelectedItem)]
            self.window?.orderOut(nil); self.onApply?()
        }
    }
}
