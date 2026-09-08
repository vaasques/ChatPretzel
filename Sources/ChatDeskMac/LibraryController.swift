import Foundation
import ChatDeskCore

// This state is confined to the serial disk queue. No AppKit/UI data lives here.
private final class LibraryWriterState: @unchecked Sendable {
    var lastWriteSucceeded = true
}

@MainActor
final class LibraryController {
    private let queue = DispatchQueue(label: "ChatDesk.local-data", qos: .utility)
    private let store: LibraryStore
    private(set) var document = LibraryDocument()
    private(set) var ready = false
    private(set) var writable = false
    private(set) var savePending = false
    private var revision: UInt64 = 0
    private let writerState = LibraryWriterState()
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ChatDesk", isDirectory: true)
        store = LibraryStore(url: root.appendingPathComponent("library-v1.json"))
    }
    func load() {
        let store = self.store
        queue.async {
            let result = Result { try store.load() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.ready = true
                switch result {
                case .success(let document): self.document = document; self.writable = true
                case .failure: self.writable = false; self.onError?("Lokala biblioteket kunde inte läsas. Original och backup lämnas orörda. Skrivning är spärrad; se felsökningsguiden.")
                }
                self.onChange?()
            }
        }
    }
    func upsert(_ entry: LibraryEntry) {
        guard ready, writable else { onError?("Biblioteket är ännu inte skrivklart."); return }
        var next = document
        if let index = next.entries.firstIndex(where: { $0.id == entry.id }) { next.entries[index] = entry }
        else { next.entries.append(entry) }
        do { try next.validate() } catch { onError?("Posten överskrider bibliotekets storleksgräns eller har en ogiltig länk."); return }
        document = next; persist(); onChange?()
    }
    func delete(_ id: UUID) {
        guard writable else { return }
        document.entries.removeAll { $0.id == id }; persist(); onChange?()
    }
    private func persist() {
        revision &+= 1; let expected = revision; let snapshot = document; let store = self.store
        savePending = true
        let writerState = self.writerState
        queue.async {
            let result = Result { try store.save(snapshot) }
            writerState.lastWriteSucceeded = (try? result.get()) != nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.revision == expected { self.savePending = false }
                if case .failure = result {
                    self.onError?("Kunde inte spara biblioteket på disk. Ändringarna finns kvar i minnet. Exportera innan du avslutar.")
                }
                self.onChange?()
            }
        }
    }
    func export(to url: URL, completion: @escaping (Bool) -> Void) {
        let snapshot = document
        let lease = FileAccessLease(url)
        queue.async {
            let result = Result { try LibraryStore.encode(snapshot).write(to: lease.url, options: .atomic) }
            DispatchQueue.main.async { completion((try? result.get()) != nil) }
        }
    }
    func importFile(_ url: URL) {
        guard writable else { onError?("Import är spärrad när det befintliga biblioteket inte kan läsas."); return }
        let lease = FileAccessLease(url)
        queue.async {
            let result = Result { try LibraryStore.decode(LibraryStore.readBounded(lease.url)) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .failure: self.onError?("Ogiltig eller för stor biblioteksexport. Inget importerades.")
                case .success(let imported):
                    var next = self.document
                    let existing = Set(next.entries.map(\.id))
                    next.entries += imported.entries.filter { !existing.contains($0.id) }
                    do { try next.validate() } catch { self.onError?("Importen skulle överskrida gränsen på 500 poster."); return }
                    self.document = next; self.persist(); self.onChange?()
                }
            }
        }
    }
    /// Used only during explicit app quit; small local writes, not any network work.
    func finishWrites() -> Bool {
        let state = writerState
        return queue.sync { state.lastWriteSucceeded }
    }
}
