import AppKit
import ChatDeskCore

@MainActor
final class LibraryPanel: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
                          NSSearchFieldDelegate, NSTextViewDelegate, NSWindowDelegate {
    let model: LibraryController
    let table = NSTableView()
    let search = NSSearchField()
    let titleField = NSTextField()
    let tagsField = NSTextField()
    let body = NSTextView()
    let kindPicker = NSPopUpButton()
    let linkLabel = NSTextField(wrappingLabelWithString: "")
    private var visible: [LibraryEntry] = []
    private var selectedID: UUID?
    private var dirty = false
    private var filling = false
    var onInsert: ((String) -> Void)?
    var onOpen: ((URL) -> Void)?

    init(model: LibraryController) {
        self.model = model
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 850, height: 570),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Lokalt bibliotek"; panel.isReleasedWhenClosed = false
        super.init(window: panel); panel.delegate = self
        search.placeholderString = "Sök titel, text och taggar"; search.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry")); column.title = "Poster"; column.width = 235
        table.addTableColumn(column); table.delegate = self; table.dataSource = self; table.rowHeight = 34
        let listScroll = NSScrollView(); listScroll.documentView = table; listScroll.hasVerticalScroller = true
        let addRow = NSStackView(views: [button("Ny prompt", #selector(addPrompt)), button("Ny anteckning", #selector(addNote))]); addRow.spacing = 6
        let left = NSStackView(views: [search, listScroll, addRow]); left.orientation = .vertical; left.alignment = .leading; left.spacing = 10
        left.widthAnchor.constraint(equalToConstant: 260).isActive = true
        for view in [search, listScroll, addRow] { view.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true }
        listScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        titleField.placeholderString = "Titel"; titleField.delegate = self
        tagsField.placeholderString = "Taggar, separerade med komma"; tagsField.delegate = self
        kindPicker.addItems(withTitles: ["Prompt", "Bokmärke", "Anteckning", "Sparat utkast"])
        kindPicker.target = self; kindPicker.action = #selector(markDirty)
        body.isRichText = false; body.font = .systemFont(ofSize: 14); body.delegate = self
        body.isAutomaticQuoteSubstitutionEnabled = false; body.isAutomaticDashSubstitutionEnabled = false
        body.isVerticallyResizable = true; body.isHorizontallyResizable = false; body.autoresizingMask = [.width]
        body.textContainer?.widthTracksTextView = true
        let editorScroll = NSScrollView(); editorScroll.documentView = body; editorScroll.hasVerticalScroller = true; editorScroll.borderType = .bezelBorder
        let commands = NSStackView(views: [button("Spara", #selector(save)), button("Kopiera", #selector(copyBody)),
            button("Infoga i chatten", #selector(insert)), button("Öppna länk", #selector(openLink)), button("Radera", #selector(deleteEntry))])
        commands.spacing = 8; commands.distribution = .fillProportionally
        let transfer = NSStackView(views: [button("Exportera JSON…", #selector(exportData)), button("Importera JSON…", #selector(importData))]); transfer.spacing = 8
        let privacy = NSTextField(wrappingLabelWithString: "Poster sparas som lokal JSON. Ingen molnsynk. {{variabel}} i prompter frågas efter vid infogning. Inget skickas automatiskt.")
        privacy.textColor = .secondaryLabelColor; privacy.font = .systemFont(ofSize: 11)
        let right = NSStackView(views: [kindPicker, titleField, tagsField, linkLabel, editorScroll, commands, transfer, privacy])
        right.orientation = .vertical; right.alignment = .leading; right.spacing = 10
        for view in [titleField, tagsField, linkLabel, editorScroll, commands, transfer, privacy] {
            view.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        }
        editorScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        let layout = NSStackView(views: [left, right]); layout.spacing = 18; layout.alignment = .top
        layout.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        layout.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView(); panel.contentView = root; root.addSubview(layout)
        NSLayoutConstraint.activate([layout.leadingAnchor.constraint(equalTo: root.leadingAnchor), layout.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            layout.topAnchor.constraint(equalTo: root.topAnchor), layout.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            left.heightAnchor.constraint(equalTo: layout.heightAnchor, constant: -32), right.heightAnchor.constraint(equalTo: left.heightAnchor)])
        model.onChange = { [weak self] in self?.refresh() }; refresh()
    }
    required init?(coder: NSCoder) { nil }
    private func button(_ title: String, _ action: Selector) -> NSButton { NSButton(title: title, target: self, action: action) }
    private var selected: LibraryEntry? { model.document.entries.first { $0.id == selectedID } }
    private var pickedKind: LibraryEntry.Kind { [.prompt, .bookmark, .note, .draft][max(0, min(3, kindPicker.indexOfSelectedItem))] }
    func refresh() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visible = model.document.entries.filter { query.isEmpty || ($0.title + " " + $0.tags + " " + $0.text).localizedCaseInsensitiveContains(query) }
            .sorted { $0.updatedAt > $1.updatedAt }
        filling = true; table.reloadData()
        if let index = visible.firstIndex(where: { $0.id == selectedID }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        filling = false
        if !dirty { fillEditor() }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visible.indices.contains(row) else { return nil }
        let label = NSTextField(labelWithString: visible[row].title.isEmpty ? "Utan titel" : visible[row].title)
        label.lineBreakMode = .byTruncatingTail; return label
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { filling || allowLeave() }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !filling, visible.indices.contains(table.selectedRow) else { return }
        selectedID = visible[table.selectedRow].id; dirty = false; fillEditor()
    }
    private func fillEditor() {
        filling = true; defer { filling = false }
        titleField.stringValue = selected?.title ?? ""; tagsField.stringValue = selected?.tags ?? ""; body.string = selected?.text ?? ""
        linkLabel.stringValue = selected?.url ?? ""
        let index = [LibraryEntry.Kind.prompt, .bookmark, .note, .draft].firstIndex(of: selected?.kind ?? .prompt) ?? 0
        kindPicker.selectItem(at: index)
    }
    func controlTextDidChange(_ obj: Notification) {
        if obj.object as AnyObject? === search { refresh() } else { markDirty() }
    }
    func textDidChange(_ notification: Notification) { markDirty() }
    @objc private func markDirty() { if !filling { dirty = true } }
    func add(_ entry: LibraryEntry) {
        guard allowLeave() else { return }
        selectedID = entry.id; dirty = false; model.upsert(entry); refresh(); showWindow(nil); window?.makeKeyAndOrderFront(nil)
    }
    @objc private func addPrompt() { add(LibraryEntry(kind: .prompt, title: "Ny prompt")) }
    @objc private func addNote() { add(LibraryEntry(kind: .note, title: "Ny anteckning")) }
    @objc private func save() {
        guard var entry = selected else { return }
        entry.title = titleField.stringValue; entry.tags = tagsField.stringValue; entry.text = body.string
        entry.kind = pickedKind; entry.updatedAt = Date()
        var probe = model.document
        if let i = probe.entries.firstIndex(where: { $0.id == entry.id }) { probe.entries[i] = entry }
        do { try probe.validate() } catch { model.onError?("Texten är för stor eller posten ogiltig. Den är inte sparad."); return }
        guard model.writable else { return }
        dirty = false; model.upsert(entry)
    }
    @objc private func copyBody() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(body.string, forType: .string) }
    @objc private func insert() { onInsert?(body.string) }
    @objc private func openLink() { if let value = selected?.url, let url = URL(string: value), NavigationPolicy().isChat(url) { onOpen?(url) } }
    @objc private func deleteEntry() {
        guard let entry = selected else { return }
        let alert = NSAlert(); alert.messageText = "Radera den lokala posten?"; alert.informativeText = "Detta raderar inte chatten hos ChatGPT."
        alert.addButton(withTitle: "Radera"); alert.addButton(withTitle: "Avbryt")
        if alert.runModal() == .alertFirstButtonReturn { dirty = false; selectedID = nil; model.delete(entry.id); refresh() }
    }
    @objc private func exportData() {
        guard let window else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "ChatPretzel-bibliotek.json"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.model.export(to: url) { [weak self] ok in if !ok { self?.model.onError?("Export misslyckades.") } }
        }
    }
    @objc private func importData() {
        guard let window, allowLeave() else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.model.importFile(url) }
        }
    }
    func allowLeave() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert(); alert.messageText = "Spara ändringarna i posten?"
        alert.addButton(withTitle: "Spara"); alert.addButton(withTitle: "Kasta ändringar"); alert.addButton(withTitle: "Stanna")
        switch alert.runModal() {
        case .alertFirstButtonReturn: save(); return !dirty
        case .alertSecondButtonReturn: dirty = false; return true
        default: return false
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { allowLeave() }
}
