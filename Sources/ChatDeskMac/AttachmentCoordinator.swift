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
    var generation: () -> UInt64 = { 0 }
    let adapter: WebAdapter
    var isBusy: Bool { preparingID != nil || pending != nil }
    var hasPendingPicker: Bool { pending != nil }
    init(adapter: WebAdapter) { self.adapter = adapter }

    /// Source is a native gesture. Paths/URLs are never supplied by JavaScript.
    func start(_ selection: FileSelection, requireFocus: Bool) {
        guard !isBusy else { onNotice?("En filoperation pågår. Vänta eller avbryt den först."); return }
        guard !selection.urls.isEmpty, selection.urls.count <= 100 else {
            onNotice?("Välj 1–100 filer per lokal operation. Tjänstens egna gränser gäller också."); return
        }
        guard records.count + selection.urls.count <= 500 else {
            onNotice?("Den lokala bilagehistoriken är full (500 rader). Rensa avslutad historik i bilagepanelen; inga nya filer skickades."); return
        }
        guard retainedLeases.count < 8 else {
            onNotice?("Kontrollera tidigare bilagor och bekräfta dem i filpanelen innan fler skickas."); return
        }
        if selection.rejectedRepresentations > 0 {
            addRecords(selection)
            fail(selection.id, "Hela urvalet kunde inte läsas (\(selection.rejectedRepresentations) filreferenser). Ingen delmängd skickades. Välj originalfilerna igen.")
            return
        }
        preparingID = selection.id
        let currentGeneration = generation()
        addRecords(selection)
        adapter.call("context") { [weak self] result in
            guard let self, self.preparingID == selection.id else { return }
            guard case .success(let info) = result, let identity = self.identity(info, generation: currentGeneration),
                  info["hasComposer"] as? Bool == true,
                  (!requireFocus || info["focused"] as? Bool == true) else {
                self.fail(selection.id, "Meddelandefältet saknas eller saknar fokus. Ingen fil skickades."); return
            }
            let leases = selection.urls.map(FileAccessLease.init)
            self.validate(leases) { [weak self] results in
                guard let self, self.preparingID == selection.id else { return }
                guard self.sameNativePage(identity) else { self.cancel(reason: "Sidan ändrades under filkontrollen."); return }
                let valid = self.applyValidation(selection: selection, results: results)
                guard valid.files.count == selection.urls.count, !valid.files.isEmpty else {
                    self.fail(selection.id, "Alla originalfiler är inte läsbara. Ingen delmängd skickades; se bilagepanelen.")
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
                        if case .success(let info) = result { message = info["error"] as? String ?? "Sidan ändrades." }
                        else { message = "WebKit kunde inte förbereda sidans filkontroll." }
                        self.fail(selection.id, message); return
                    }
                    self.preparingID = nil
                    self.pending = Pending(permit: permit, selectionID: selection.id, files: valid.files, recordIDs: valid.ids)
                    valid.ids.forEach { self.set($0, .waitingForWebKit) }
                    let task = DispatchWorkItem { [weak self] in
                        guard let self, self.pending?.selectionID == selection.id else { return }
                        self.fail(selection.id, "WebKit öppnade ingen godkänd filkontroll. Inga filer överlämnades. Testa system-paste separat; ingen automatisk reservväg körs.")
                    }
                    self.timeout = task; DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
                    self.adapter.call("triggerFiles", arguments: ["token": permit.token.uuidString]) { [weak self] result in
                        guard let self, self.pending?.selectionID == selection.id else { return }
                        if case .success(let info) = result, info["ok"] as? Bool == true { return }
                        self.fail(selection.id, "Filkontrollen kunde inte öppnas. Inga filer överlämnades.")
                    }
                    self.onChange?()
                }
            }
        }
    }

    /// Called ONLY by WKUIDelegate. Returning true means this coordinator owns completion.
    func handlePicker(parameters: WKOpenPanelParameters, frame: WKFrameInfo,
                      completion: @escaping ([URL]?) -> Void) -> Bool {
        guard let p = pending else { return false }
        guard frame.isMainFrame, adapter.policy.allowsAdapter(frame.request.url),
              frame.request.url?.absoluteString == p.permit.page.href,
              parameters.allowsMultipleSelection || p.files.count == 1 else {
            completion(nil); fail(p.selectionID, "Fel frame eller filkontroll. Inget överlämnades."); return true
        }
        adapter.call("validateFiles", arguments: ["token": p.permit.token.uuidString]) { [weak self] result in
            guard let self, var current = self.pending, current.selectionID == p.selectionID else { completion(nil); return }
            guard case .success(let info) = result, info["ok"] as? Bool == true,
                  let identity = self.identity(info, generation: self.generation()),
                  self.sameNativePage(identity) else {
                completion(nil); self.fail(p.selectionID, "Sidans filkontroll ändrades. Inget överlämnades."); return
            }
            do { try current.permit.consume(page: identity, mainFrame: frame.isMainFrame) }
            catch { completion(nil); self.fail(p.selectionID, "Filoperationens tillstånd är för gammalt eller hör till en annan sida."); return }
            self.timeout?.cancel(); self.timeout = nil; self.pending = nil
            self.retainedLeases[current.selectionID] = current.files.map(\.lease)
            // Only original URL objects cross this native callback. WebKit reads the bytes.
            completion(current.files.map(\.url))
            current.recordIDs.forEach { self.set($0, .handedToWebKit) }
            self.adapter.call("cancelFiles") { _ in }
            self.onNotice?("\(current.files.count) originalfiler överlämnade till WebKit. Kontrollera uppladdningen i ChatGPT; detta är inte en serverbekräftelse.")
            self.onChange?()
        }
        return true
    }

    /// Normal user-visible NSOpenPanel uses the same validator and records, without adapter automation.
    func deliverPanelSelection(_ urls: [URL], pageURL: URL, pageGeneration: UInt64,
                               completion: @escaping ([URL]?) -> Void) {
        guard !isBusy, retainedLeases.count < 8, urls.count <= 100 else { completion(nil); onNotice?("För många pågående filoperationer."); return }
        let selection = FileSelection(urls: urls)
        guard records.count + selection.urls.count <= 500 else {
            completion(nil); onNotice?("Rensa avslutad lokal bilagehistorik innan fler filer väljs."); return
        }
        preparingID = selection.id; addRecords(selection)
        validate(selection.urls.map(FileAccessLease.init)) { [weak self] results in
            guard let self, self.preparingID == selection.id else { completion(nil); return }
            guard self.generation() == pageGeneration, self.adapter.webView?.url == pageURL else {
                completion(nil); self.cancel(reason: "Sidan ändrades medan filväljaren var öppen."); return
            }
            let valid = self.applyValidation(selection: selection, results: results)
            self.preparingID = nil
            guard valid.files.count == selection.urls.count, !valid.files.isEmpty else {
                completion(nil)
                self.fail(selection.id, "Alla valda filer är inte läsbara. Ingen delmängd överlämnades.")
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
            onNotice?("\(selection.rejectedRepresentations) filrepresentationer stöds inte. Övriga kontrolleras; batchen är inte komplett.")
        }
        onNotice?("\(selection.urls.count) filer identifierade lokalt. Kontrollerar åtkomst; inget är ännu uppladdat.")
        onChange?()
    }
    private func applyValidation(selection: FileSelection, results: [Result<CheckedFile, Error>]) -> (files: [CheckedFile], ids: [UUID]) {
        let indices = records.indices.filter { records[$0].operationID == selection.id }
        var files: [CheckedFile] = []; var ids: [UUID] = []
        for (index, result) in zip(indices, results) {
            switch result {
            case .success(let file): records[index].byteCount = file.size; files.append(file); ids.append(records[index].id)
            case .failure(let error): records[index].transition(to: .failed,
                    detail: (error as? FileValidationError)?.message ?? "Filen kunde inte läsas.")
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
        adapter.call("cancelFiles") { _ in }
        onNotice?(message); onChange?()
    }
    func cancel(reason: String = "Avbruten av användaren.") {
        timeout?.cancel(); timeout = nil; preparingID = nil; pending = nil
        for index in records.indices {
            if [.identified, .checking, .waitingForWebKit].contains(records[index].state) {
                records[index].transition(to: .cancelled, detail: reason)
            }
        }
        adapter.call("cancelFiles") { _ in }; onChange?()
    }
    func navigationChanged() {
        cancel(reason: "Sida eller konversation ändrades.")
        for index in records.indices where records[index].state == .handedToWebKit {
            records[index].transition(to: .unknown, detail: "Sidan ändrades efter överlämning. Uppladdningen kan inte återkallas här.")
        }
        retainedLeases.removeAll(); onChange?()
    }
    func confirm(_ ids: Set<UUID>) {
        for index in records.indices where ids.contains(records[index].id) {
            if [.handedToWebKit, .unknown].contains(records[index].state) {
                records[index].transition(to: .userConfirmed, detail: "Manuellt kontrollerad i webbgränssnittet. Ingen automatisk serververifiering.")
            }
        }
        let operations = Array(retainedLeases.keys)
        for operation in operations where !records.contains(where: {
            $0.operationID == operation && [.handedToWebKit, .unknown].contains($0.state)
        }) { retainedLeases.removeValue(forKey: operation) }
        onChange?()
    }
    func clearResolved() {
        records.removeAll { [.failed, .cancelled, .userConfirmed, .unknown].contains($0.state) }; onChange?()
    }
}
