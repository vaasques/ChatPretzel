import AppKit

@MainActor
final class SettingsPanel: NSWindowController {
    let preferences: Preferences
    let safe = NSButton(checkboxWithTitle: "Safe Mode: disable ChatPretzel web scripts", target: nil, action: nil)
    let paste = NSButton(checkboxWithTitle: "Assisted attachment paste through WebKit's file control (not live-verified)", target: nil, action: nil)
    let cv = NSButton(checkboxWithTitle: "Use Control+C and Control+V inside the app", target: nil, action: nil)
    let hotKey = NSButton(checkboxWithTitle: "Global shortcut shows the same window", target: nil, action: nil)
    let shortcut = NSPopUpButton()
    let width = NSPopUpButton()
    var onApply: (() -> Void)?
    init(preferences: Preferences) {
        self.preferences = preferences
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 630, height: 365),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "ChatPretzel Settings"; panel.isReleasedWhenClosed = false
        super.init(window: panel)
        safe.state = preferences.safeMode ? .on : .off; paste.state = preferences.assistedPaste ? .on : .off
        cv.state = preferences.controlCV ? .on : .off; hotKey.state = preferences.globalHotKey ? .on : .off
        shortcut.addItems(withTitles: ["Control + Option + Space", "Command + Option + Space"])
        shortcut.selectItem(at: preferences.hotKeyUsesCommand ? 1 : 0)
        width.addItems(withTitles: ["Website default reading width", "880 px", "1040 px", "1280 px"])
        width.selectItem(at: [0, 880, 1040, 1280].firstIndex(of: preferences.readingWidth) ?? 0)
        let info = NSTextField(wrappingLabelWithString: "Changes reload the page. Existing web attachments may need to be selected again. Your account and local library are not deleted. With attachment assistance off, WebKit uses normal paste with no automatic fallback.")
        info.textColor = .secondaryLabelColor
        let button = NSButton(title: "Save and Reload…", target: self, action: #selector(apply))
        installPanelContent(panel, views: [safe, paste, cv, hotKey, shortcut, width, info, button], flexible: info)
    }
    required init?(coder: NSCoder) { nil }
    @objc private func apply() {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = "Reload ChatGPT?"
        alert.informativeText = "Copy any important unsent text first. Uploaded but unsent attachments may be lost when the page reloads."
        alert.addButton(withTitle: "Save and Reload"); alert.addButton(withTitle: "Cancel")
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
