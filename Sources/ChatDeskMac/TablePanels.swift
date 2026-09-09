import AppKit
import ChatDeskCore

@MainActor
final class TransferPanel: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    let coordinator: AttachmentCoordinator
    let table = NSTableView()
    init(coordinator: AttachmentCoordinator) {
        self.coordinator = coordinator
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 850, height: 390),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Attachments • Local Status"; panel.isReleasedWhenClosed = false
        super.init(window: panel)
        for (id, title, width) in [("name", "File", 230.0), ("state", "Status", 290.0), ("detail", "Information", 290.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width; table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self; table.allowsMultipleSelection = true; table.rowHeight = 28
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let info = NSTextField(wrappingLabelWithString: "Handed to WebKit does not mean fully uploaded. Confirm only files you have checked in ChatGPT yourself. Cancel stops only files that have not yet been handed over.")
        let buttons = NSStackView(views: [button("Cancel Pending", #selector(cancel)), button("Confirm Selected", #selector(confirm)), button("Clear Completed History", #selector(clear))])
        buttons.spacing = 10
        installPanelContent(panel, views: [info, scroll, buttons], flexible: scroll)
    }
    required init?(coder: NSCoder) { nil }
    func numberOfRows(in tableView: NSTableView) -> Int { coordinator.records.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard coordinator.records.indices.contains(row) else { return nil }
        let record = coordinator.records[row]
        let value: String
        switch tableColumn?.identifier.rawValue {
        case "name": value = record.filename
        case "state": value = record.state.label
        default: value = record.detail
        }
        let label = NSTextField(labelWithString: value); label.lineBreakMode = .byTruncatingTail; label.toolTip = value; return label
    }
    func refresh() { table.reloadData() }
    private func button(_ title: String, _ action: Selector) -> NSButton { NSButton(title: title, target: self, action: action) }
    @objc private func cancel() { coordinator.cancel(); refresh() }
    @objc private func clear() { coordinator.clearResolved(); refresh() }
    @objc private func confirm() {
        let ids = Set(table.selectedRowIndexes.compactMap { coordinator.records.indices.contains($0) ? coordinator.records[$0].id : nil })
        guard !ids.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "Have you checked the selected attachments?"
        alert.informativeText = "This is your manual confirmation, not an automated test of the service."
        alert.addButton(withTitle: "Yes, They Are Attached"); alert.addButton(withTitle: "Cancel")
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] result in
            if result == .alertFirstButtonReturn { self?.coordinator.confirm(ids); self?.refresh() }
        }
    }
}

@MainActor
final class DownloadsPanel: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    let coordinator: DownloadCoordinator
    let table = NSTableView()
    init(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 340),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Downloads"; panel.isReleasedWhenClosed = false
        super.init(window: panel)
        for (id, title, width) in [("name", "File", 300.0), ("state", "Status", 360.0)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); col.title = title; col.width = width; table.addTableColumn(col)
        }
        table.dataSource = self; table.delegate = self; table.allowsMultipleSelection = true; table.rowHeight = 28
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        let buttons = NSStackView(views: [NSButton(title: "Show in Finder", target: self, action: #selector(reveal)),
                                         NSButton(title: "Cancel Selected", target: self, action: #selector(cancel))]); buttons.spacing = 10
        installPanelContent(panel, views: [scroll, buttons], flexible: scroll)
    }
    required init?(coder: NSCoder) { nil }
    func numberOfRows(in tableView: NSTableView) -> Int { coordinator.rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard coordinator.rows.indices.contains(row) else { return nil }
        let item = coordinator.rows[row]
        return NSTextField(labelWithString: tableColumn?.identifier.rawValue == "name" ? item.name : item.state)
    }
    func refresh() { table.reloadData() }
    private var selected: Set<ObjectIdentifier> { Set(table.selectedRowIndexes.compactMap { coordinator.rows.indices.contains($0) ? coordinator.rows[$0].id : nil }) }
    @objc private func reveal() { coordinator.reveal(selected) }
    @objc private func cancel() { coordinator.cancel(selected) }
}

@MainActor
func installPanelContent(_ window: NSWindow, views: [NSView], flexible: NSView) {
    let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let root = NSView(); window.contentView = root; root.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        stack.topAnchor.constraint(equalTo: root.topAnchor), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)])
    for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true }
    flexible.setContentHuggingPriority(.defaultLow, for: .vertical)
    flexible.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
}
