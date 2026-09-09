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
        panel.title = "Local Library"; panel.isReleasedWhenClosed = false
        super.init(window: panel); panel.delegate = self
        search.placeholderString = "Search titles, text, and tags"; search.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry")); column.title = "Entries"; column.width = 235
        table.addTableColumn(column); table.delegate = self; table.dataSource = self; table.rowHeight = 34
        let listScroll = NSScrollView(); listScroll.documentView = table; listScroll.hasVerticalScroller = true
        let addRow = NSStackView(views: [button("New Prompt", #selector(addPrompt)), button("New Note", #selector(addNote))]); addRow.spacing = 6
        let left = NSStackView(views: [search, listScroll, addRow]); left.orientation = .vertical; left.alignment = .leading; left.spacing = 10
        left.widthAnchor.constraint(equalToConstant: 260).isActive = true
        for view in [search, listScroll, addRow] { view.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true }
        listScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        titleField.placeholderString = "Title"; titleField.delegate = self
        tagsField.placeholderString = "Tags, separated by commas"; tagsField.delegate = self
        kindPicker.addItems(withTitles: ["Prompt", "Bookmark", "Note", "Saved Draft"])
        kindPicker.target = self; kindPicker.action = #selector(markDirty)
        body.isRichText = false; body.font = .systemFont(ofSize: 14); body.delegate = self
        body.isAutomaticQuoteSubstitutionEnabled = false; body.isAutomaticDashSubstitutionEnabled = false
        body.isVerticallyResizable = true; body.isHorizontallyResizable = false; body.autoresizingMask = [.width]
        body.textContainer?.widthTracksTextView = true
        let editorScroll = NSScrollView(); editorScroll.documentView = body; editorScroll.hasVerticalScroller = true; editorScroll.borderType = .bezelBorder
        let commands = NSStackView(views: [button("Save", #selector(save)), button("Copy", #selector(copyBody)),
            button("Insert into Chat", #selector(insert)), button("Open Link", #selector(openLink)), button("Delete", #selector(deleteEntry))])
        commands.spacing = 8; commands.distribution = .fillProportionally
        let transfer = NSStackView(views: [button("Export JSON…", #selector(exportData)), button("Import JSON…", #selector(importData))]); transfer.spacing = 8
        let privacy = NSTextField(wrappingLabelWithString: "Entries are stored as local JSON. There is no cloud sync. Prompt variables such as {{variable}} are requested when inserted. Nothing is sent automatically.")
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
        let label = NSTextField(labelWithString: visible[row].title.isEmpty ? "Untitled" : visible[row].title)
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
    @objc private func addPrompt() { add(LibraryEntry(kind: .prompt, title: "New Prompt")) }
    @objc private func addNote() { add(LibraryEntry(kind: .note, title: "New Note")) }
    @objc private func save() {
        guard var entry = selected else { return }
        entry.title = titleField.stringValue; entry.tags = tagsField.stringValue; entry.text = body.string
        entry.kind = pickedKind; entry.updatedAt = Date()
        var probe = model.document
        if let i = probe.entries.firstIndex(where: { $0.id == entry.id }) { probe.entries[i] = entry }
        do { try probe.validate() } catch { model.onError?("The text is too large or the entry is invalid. It was not saved."); return }
        guard model.writable else { return }
        dirty = false; model.upsert(entry)
    }
    @objc private func copyBody() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(body.string, forType: .string) }
    @objc private func insert() { onInsert?(body.string) }
    @objc private func openLink() { if let value = selected?.url, let url = URL(string: value), NavigationPolicy().isChat(url) { onOpen?(url) } }
    @objc private func deleteEntry() {
        guard let entry = selected else { return }
        let alert = NSAlert(); alert.messageText = "Delete the local entry?"; alert.informativeText = "This does not delete the chat from ChatGPT."
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { dirty = false; selectedID = nil; model.delete(entry.id); refresh() }
    }
    @objc private func exportData() {
        guard let window else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "ChatPretzel-library.json"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.model.export(to: url) { [weak self] ok in if !ok { self?.model.onError?("Export failed.") } }
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
        let alert = NSAlert(); alert.messageText = "Save changes to this entry?"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Discard Changes"); alert.addButton(withTitle: "Stay")
        switch alert.runModal() {
        case .alertFirstButtonReturn: save(); return !dirty
        case .alertSecondButtonReturn: dirty = false; return true
        default: return false
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { allowLeave() }
}
