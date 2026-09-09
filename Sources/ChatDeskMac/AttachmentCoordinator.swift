import AppKit
import WebKit
import ChatDeskCore

@MainActor
final class AttachmentCoordinator {
    struct Pending {
        var permit: UploadPermit
        let selectionID: UUID
        let files: [CheckedFile]
        let recordIDs: [UUID]
    }
    private(set) var records: [AttachmentRecord] = []
    private var preparingID: UUID?
    private var pending: Pending?
    private var timeout: DispatchWorkItem?
    private var retainedLeases: [UUID: [FileAccessLease]] = [:]
    private let io = DispatchQueue(label: "ChatDesk.file-validation", qos: .userInitiated)
    var onChange: (() -> Void)?
    var onNotice: ((String) -> Void)?
    var onReleaseOperation: ((UUID) -> Void)?
    var generation: () -> UInt64 = { 0 }
    let adapter: WebAdapter
    var isBusy: Bool { preparingID != nil || pending != nil }
    var hasPendingPicker: Bool { pending != nil }
    init(adapter: WebAdapter) { self.adapter = adapter }

    /// Source is a native gesture. Paths/URLs are never supplied by JavaScript.
    @discardableResult
    func start(_ selection: FileSelection, requireFocus: Bool) -> Bool {
        guard !isBusy else { onNotice?("A file operation is in progress. Wait for it to finish or cancel it first."); return false }
        guard !selection.urls.isEmpty, selection.urls.count <= 100 else {
            onNotice?("Choose 1–100 files per local operation. The service's own limits also apply."); return false
        }
        guard records.count + selection.urls.count <= 500 else {
            onNotice?("The local attachment history is full (500 rows). Clear completed history in the attachment panel; no new files were sent."); return false
        }
        guard retainedLeases.count < 8 else {
            onNotice?("Check earlier attachments and confirm them in the attachment panel before sending more."); return false
        }
        if selection.rejectedRepresentations > 0 {
            addRecords(selection)
            fail(selection.id, "The entire selection could not be read (\(selection.rejectedRepresentations) file references). No partial selection was sent. Choose the original files again.")
            return true
        }
        preparingID = selection.id
        let currentGeneration = generation()
        addRecords(selection)
        adapter.call("context") { [weak self] result in
            guard let self, self.preparingID == selection.id else { return }
            guard case .success(let info) = result, let identity = self.identity(info, generation: currentGeneration),
                  info["hasComposer"] as? Bool == true,
                  (!requireFocus || info["focused"] as? Bool == true) else {
                self.fail(selection.id, "The message field is missing or is not focused. No file was sent."); return
            }
            let leases = selection.urls.map(FileAccessLease.init)
            self.validate(leases) { [weak self] results in
                guard let self, self.preparingID == selection.id else { return }
                guard self.sameNativePage(identity) else { self.cancel(reason: "The page changed while files were being checked."); return }
                let valid = self.applyValidation(selection: selection, results: results)
                guard valid.files.count == selection.urls.count, !valid.files.isEmpty else {
                    self.fail(selection.id, "Not every original file is readable. No partial selection was sent; see the attachment panel.")
                    return
                }
                let permit = UploadPermit(page: identity)
                let descriptors = valid.files.map { ["extension": $0.url.pathExtension, "mime": $0.mime] }
                self.adapter.call("prepareFiles", arguments: ["token": permit.token.uuidString,
                                  "files": descriptors, "requireFocus": requireFocus]) { [weak self] result in
                    guard let self, self.preparingID == selection.id else { return }
                    guard case .success(let info) = result, info["ok"] as? Bool == true,
                          self.identity(info, generation: currentGeneration) == identity,
                          self.sameNativePage(identity) else {
                        let message: String
                        if case .success(let info) = result { message = info["error"] as? String ?? "The page changed." }
                        else { message = "WebKit could not prepare the page's file control." }
                        self.fail(selection.id, message); return
                    }
                    self.preparingID = nil
                    self.pending = Pending(permit: permit, selectionID: selection.id, files: valid.files, recordIDs: valid.ids)
                    valid.ids.forEach { self.set($0, .waitingForWebKit) }
                    let task = DispatchWorkItem { [weak self] in
                        guard let self, self.pending?.selectionID == selection.id else { return }
                        self.fail(selection.id, "WebKit did not open an approved file control. No files were handed over. Test normal system paste separately; no automatic fallback was used.")
                    }
                    self.timeout = task; DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
                    self.adapter.call("triggerFiles", arguments: ["token": permit.token.uuidString]) { [weak self] result in
                        guard let self, self.pending?.selectionID == selection.id else { return }
                        if case .success(let info) = result, info["ok"] as? Bool == true { return }
                        self.fail(selection.id, "The file control could not be opened. No files were handed over.")
                    }
                    self.onChange?()
                }
            }
        }
        return true
    }

    /// Called ONLY by WKUIDelegate. Returning true means this coordinator owns completion.
    func handlePicker(parameters: WKOpenPanelParameters, frame: WKFrameInfo,
                      completion: @escaping ([URL]?) -> Void) -> Bool {
        guard let p = pending else { return false }
        guard frame.isMainFrame, adapter.policy.allowsAdapter(frame.request.url),
              frame.request.url?.absoluteString == p.permit.page.href,
              parameters.allowsMultipleSelection || p.files.count == 1 else {
            completion(nil); fail(p.selectionID, "Wrong frame or file control. Nothing was handed over."); return true
        }
        adapter.call("validateFiles", arguments: ["token": p.permit.token.uuidString]) { [weak self] result in
            guard let self, var current = self.pending, current.selectionID == p.selectionID else { completion(nil); return }
            guard case .success(let info) = result, info["ok"] as? Bool == true,
                  let identity = self.identity(info, generation: self.generation()),
                  self.sameNativePage(identity) else {
                completion(nil); self.fail(p.selectionID, "The page's file control changed. Nothing was handed over."); return
            }
            do { try current.permit.consume(page: identity, mainFrame: frame.isMainFrame) }
            catch { completion(nil); self.fail(p.selectionID, "The file operation is stale or belongs to another page."); return }
            self.timeout?.cancel(); self.timeout = nil; self.pending = nil
            self.retainedLeases[current.selectionID] = current.files.map(\.lease)
            // Only original URL objects cross this native callback. WebKit reads the bytes.
            completion(current.files.map(\.url))
            current.recordIDs.forEach { self.set($0, .handedToWebKit) }
            self.adapter.call("cancelFiles") { _ in }
            self.onNotice?("\(current.files.count) original files handed to WebKit. Check the upload in ChatGPT; this is not server confirmation.")
            self.onChange?()
        }
        return true
    }

    /// Normal user-visible NSOpenPanel uses the same validator and records, without adapter automation.
    func deliverPanelSelection(_ urls: [URL], pageURL: URL, pageGeneration: UInt64,
                               completion: @escaping ([URL]?) -> Void) {
        guard !isBusy, retainedLeases.count < 8, urls.count <= 100 else { completion(nil); onNotice?("Too many file operations are in progress."); return }
        let selection = FileSelection(urls: urls)
        guard records.count + selection.urls.count <= 500 else {
            completion(nil); onNotice?("Clear completed local attachment history before choosing more files."); return
        }
        preparingID = selection.id; addRecords(selection)
        validate(selection.urls.map(FileAccessLease.init)) { [weak self] results in
            guard let self, self.preparingID == selection.id else { completion(nil); return }
            guard self.generation() == pageGeneration, self.adapter.webView?.url == pageURL else {
                completion(nil); self.cancel(reason: "The page changed while the file picker was open."); return
            }
            let valid = self.applyValidation(selection: selection, results: results)
            self.preparingID = nil
            guard valid.files.count == selection.urls.count, !valid.files.isEmpty else {
                completion(nil)
                self.fail(selection.id, "Not every selected file is readable. No partial selection was handed over.")
                return
            }
            self.retainedLeases[selection.id] = valid.files.map(\.lease)
            valid.ids.forEach { self.set($0, .waitingForWebKit) }
            completion(valid.files.map(\.url))
            valid.ids.forEach { self.set($0, .handedToWebKit) }
            self.onChange?()
        }
    }
    private func validate(_ leases: [FileAccessLease], completion: @escaping ([Result<CheckedFile, Error>]) -> Void) {
        io.async {
            let results = leases.map { lease -> Result<CheckedFile, Error> in Result { try FileValidator.check(lease) } }
            DispatchQueue.main.async { completion(results) }
        }
    }
    private func addRecords(_ selection: FileSelection) {
        // Keep unresolved rows; only trim resolved history. Never hide a still-active grant.
        if records.count > 200 { records.removeAll { [.failed, .cancelled, .userConfirmed].contains($0.state) } }
        for url in selection.urls {
            var record = AttachmentRecord(operationID: selection.id, filename: url.lastPathComponent)
            record.transition(to: .checking); records.append(record)
        }
        if selection.rejectedRepresentations > 0 {
            onNotice?("\(selection.rejectedRepresentations) file representations are unsupported. The others are being checked; the batch is incomplete.")
        }
        onNotice?("\(selection.urls.count) files identified locally. Checking access; nothing has been uploaded yet.")
        onChange?()
    }
    private func applyValidation(selection: FileSelection, results: [Result<CheckedFile, Error>]) -> (files: [CheckedFile], ids: [UUID]) {
        let indices = records.indices.filter { records[$0].operationID == selection.id }
        var files: [CheckedFile] = []; var ids: [UUID] = []
        for (index, result) in zip(indices, results) {
            switch result {
            case .success(let file): records[index].byteCount = file.size; files.append(file); ids.append(records[index].id)
            case .failure(let error): records[index].transition(to: .failed,
                    detail: (error as? FileValidationError)?.message ?? "The file could not be read.")
            }
        }
        onChange?(); return (files, ids)
    }
    private func identity(_ object: [String: Any], generation: UInt64) -> PageIdentity? {
        guard let href = object["href"] as? String, href.count < 8192,
              adapter.policy.allowsAdapter(URL(string: href)), let doc = object["documentID"] as? String,
              !doc.isEmpty, doc.count <= 80 else { return nil }
        return PageIdentity(href: href, documentID: doc, generation: generation)
    }
    private func sameNativePage(_ identity: PageIdentity) -> Bool {
        generation() == identity.generation && adapter.webView?.url?.absoluteString == identity.href
    }
    private func set(_ id: UUID, _ state: AttachmentState, detail: String = "") {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].transition(to: state, detail: detail)
    }
    private func fail(_ operation: UUID, _ message: String) {
        for index in records.indices where records[index].operationID == operation {
            if [.checking, .waitingForWebKit].contains(records[index].state) {
                records[index].transition(to: .failed, detail: message)
            }
        }
        if preparingID == operation { preparingID = nil }
        if pending?.selectionID == operation { pending = nil; timeout?.cancel(); timeout = nil }
        retainedLeases.removeValue(forKey: operation)
        onReleaseOperation?(operation)
        adapter.call("cancelFiles") { _ in }
        onNotice?(message); onChange?()
    }
    func cancel(reason: String = "Cancelled by the user.") {
        let activeOperations = Set(records.filter {
            [.identified, .checking, .waitingForWebKit].contains($0.state)
        }.map(\.operationID))
        timeout?.cancel(); timeout = nil; preparingID = nil; pending = nil
        for index in records.indices {
            if [.identified, .checking, .waitingForWebKit].contains(records[index].state) {
                records[index].transition(to: .cancelled, detail: reason)
            }
        }
        activeOperations.forEach { retainedLeases.removeValue(forKey: $0); onReleaseOperation?($0) }
        adapter.call("cancelFiles") { _ in }; onChange?()
    }
    func navigationChanged() {
        let handedOperations = Set(retainedLeases.keys)
        cancel(reason: "The page or conversation changed.")
        for index in records.indices where records[index].state == .handedToWebKit {
            records[index].transition(to: .unknown, detail: "The page changed after handoff. The upload cannot be withdrawn here.")
        }
        retainedLeases.removeAll(); handedOperations.forEach { onReleaseOperation?($0) }; onChange?()
    }
    func confirm(_ ids: Set<UUID>) {
        for index in records.indices where ids.contains(records[index].id) {
            if [.handedToWebKit, .unknown].contains(records[index].state) {
                records[index].transition(to: .userConfirmed, detail: "Manually checked in the web interface. No automatic server verification.")
            }
        }
        let operations = Array(retainedLeases.keys)
        for operation in operations where !records.contains(where: {
            $0.operationID == operation && [.handedToWebKit, .unknown].contains($0.state)
        }) { retainedLeases.removeValue(forKey: operation); onReleaseOperation?(operation) }
        onChange?()
    }
    func clearResolved() {
        records.removeAll { [.failed, .cancelled, .userConfirmed, .unknown].contains($0.state) }; onChange?()
    }
}
