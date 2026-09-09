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
                case .failure: self.writable = false; self.onError?("The local library could not be read. The original and backup were left unchanged. Writing is disabled; see the troubleshooting guide.")
                }
                self.onChange?()
            }
        }
    }
    func upsert(_ entry: LibraryEntry) {
        guard ready, writable else { onError?("The library is not ready for writing yet."); return }
        var next = document
        if let index = next.entries.firstIndex(where: { $0.id == entry.id }) { next.entries[index] = entry }
        else { next.entries.append(entry) }
        do { try next.validate() } catch { onError?("The entry exceeds the library size limit or contains an invalid link."); return }
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
                    self.onError?("The library could not be saved to disk. Changes remain in memory. Export before quitting.")
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
        guard writable else { onError?("Import is disabled while the existing library cannot be read."); return }
        let lease = FileAccessLease(url)
        queue.async {
            let result = Result { try LibraryStore.decode(LibraryStore.readBounded(lease.url)) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .failure: self.onError?("The library export is invalid or too large. Nothing was imported.")
                case .success(let imported):
                    var next = self.document
                    let existing = Set(next.entries.map(\.id))
                    next.entries += imported.entries.filter { !existing.contains($0.id) }
                    do { try next.validate() } catch { self.onError?("The import would exceed the 500-entry limit."); return }
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
