import AppKit
import WebKit
import ChatDeskCore

@MainActor
final class DownloadCoordinator: NSObject, WKDownloadDelegate {
    struct Row {
        let id: ObjectIdentifier
        var name: String
        var state: String
        var destination: URL?
        var finished: Bool = false
    }
    weak var window: NSWindow?
    private var active: [ObjectIdentifier: WKDownload] = [:]
    private var destinationLeases: [ObjectIdentifier: FileAccessLease] = [:]
    private(set) var rows: [Row] = []
    var onChange: (() -> Void)?
    var onNotice: ((String) -> Void)?
    private var pendingChoices: [(WKDownload, String, (URL?) -> Void)] = []
    private var presenting = false
    func accept(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        guard active.count < 8 else {
            download.cancel { _ in }; onNotice?("At most eight downloads can run at once. The new download was cancelled."); return
        }
        if rows.count >= 100 { rows.removeAll { active[$0.id] == nil } }
        active[key] = download; download.delegate = self
        rows.append(Row(id: key, name: "Download", state: "Waiting for save location"))
        if rows.count > 100 { rows.removeAll { $0.finished } }
        onChange?()
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        pendingChoices.append((download, FilePolicy.safeDownloadName(suggestedFilename), completionHandler))
        presentNextChoice()
    }
    private func presentNextChoice() {
        guard !presenting, !pendingChoices.isEmpty else { return }
        let (download, name, completion) = pendingChoices.removeFirst()
        let key = ObjectIdentifier(download)
        guard active[key] != nil, let window, window.attachedSheet == nil else {
            completion(nil); change(key, name: name, state: "Cancelled – the save panel could not open")
            active.removeValue(forKey: key); presentNextChoice(); return
        }
        presenting = true
        let panel = NSSavePanel()
        panel.title = "Save Download"
        panel.message = "Choose a new filename. ChatPretzel does not overwrite existing files."
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { completion(nil); return }
            self.presenting = false
            guard response == .OK, let destination = panel.url, self.active[key] != nil else {
                completion(nil); self.change(key, name: name, state: "Cancelled")
                self.active.removeValue(forKey: key); self.presentNextChoice(); return
            }
            // WKDownload explicitly requires a non-existent destination. Never delete an existing file.
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                completion(nil); self.change(key, name: name, state: "Cancelled – the filename already exists")
                self.active.removeValue(forKey: key)
                self.onNotice?("The file already exists. Start the download again and choose another name.")
                self.presentNextChoice(); return
            }
            self.destinationLeases[key] = FileAccessLease(destination)
            self.change(key, name: destination.lastPathComponent, state: "Downloading", destination: destination)
            completion(destination); self.presentNextChoice()
        }
    }
    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        change(key, state: "Saved", finished: true)
        active.removeValue(forKey: key); destinationLeases.removeValue(forKey: key)
        onNotice?("The download was saved. Open Downloads to show it in Finder.")
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let key = ObjectIdentifier(download)
        // Do not log NSError.userInfo or resumeData: they may contain signed URLs or tokens.
        change(key, state: "Failed (\((error as NSError).code))")
        active.removeValue(forKey: key); destinationLeases.removeValue(forKey: key)
    }
    func cancel(_ keys: Set<ObjectIdentifier>) {
        for key in keys {
            active[key]?.cancel { _ in }
            active.removeValue(forKey: key); destinationLeases.removeValue(forKey: key)
            change(key, state: "Cancelled – any partial file was left unchanged")
        }
    }
    func cancelAll() { cancel(Set(active.keys)) }
    func reveal(_ keys: Set<ObjectIdentifier>) {
        let urls = rows.filter { keys.contains($0.id) && $0.finished }.compactMap(\.destination)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
    private func change(_ key: ObjectIdentifier, name: String? = nil, state: String,
                        destination: URL? = nil, finished: Bool = false) {
        if let index = rows.firstIndex(where: { $0.id == key }) {
            if let name { rows[index].name = name }
            if let destination { rows[index].destination = destination }
            rows[index].state = state; rows[index].finished = finished
        }
        onChange?()
    }
}
