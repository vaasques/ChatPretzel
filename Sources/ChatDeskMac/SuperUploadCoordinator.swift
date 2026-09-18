import Foundation
import NaturalLanguage
import Darwin
import WebKit
import ChatDeskCore

/// Operation-scoped copies used only when ChatGPT would otherwise receive duplicate
/// basenames. Originals are never renamed or modified.
/// This object has immutable state after creation and all filesystem mutations are
/// serialized through `SuperUploadCoordinator.io`.
final class SuperUploadFileStaging: @unchecked Sendable {
    /// A deterministic upload name. Planning is metadata-only: duplicate source
    /// files are not cloned until their ten-file batch is about to be handed to
    /// WebKit. This keeps a very large queue from creating thousands of temporary
    /// copies before the first message is even ready.
    struct PlannedFile {
        let original: URL
        let stagedName: String?

        var uploadName: String { stagedName ?? original.lastPathComponent }
    }

    let directory: URL
    private let fm = FileManager.default

    init(operationID: UUID) throws {
        directory = fm.temporaryDirectory.appendingPathComponent("ChatDesk-SuperUpload-\(operationID.uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? fm.removeItem(at: directory) }

    /// Computes duplicate-safe names in source order without accessing file bytes
    /// or creating staging copies. The result has one small metadata value per
    /// selected URL, even for queues with thousands of files.
    func plan(_ originals: [URL]) -> [PlannedFile] {
        let reservedNames = Set(originals.map { Self.nameKey($0.lastPathComponent) })
        var occurrences: Set<String> = []
        var stagedNames: Set<String> = []
        var nextSuffix: [String: Int] = [:]
        return originals.map { original in
            let base = original.lastPathComponent.precomposedStringWithCanonicalMapping
            let key = Self.nameKey(base)
            guard !occurrences.insert(key).inserted else {
                return PlannedFile(original: original, stagedName: nil)
            }
            let ext = original.pathExtension
            let stem = ext.isEmpty ? base : String(base.dropLast(ext.count + 1))
            var number = nextSuffix[key, default: 2]
            while true {
                let suffix = " \(number)"
                let maxStem = max(1, 240 - suffix.count - (ext.isEmpty ? 0 : ext.count + 1))
                var clipped = String(stem.prefix(maxStem))
                while (clipped + suffix + (ext.isEmpty ? "" : "." + ext)).utf8.count > 240, !clipped.isEmpty {
                    clipped.removeLast()
                }
                let name = ext.isEmpty ? clipped + suffix : clipped + suffix + "." + ext
                number += 1
                let nameKey = Self.nameKey(name)
                if !stagedNames.contains(nameKey), !reservedNames.contains(nameKey) {
                    stagedNames.insert(nameKey)
                    nextSuffix[key] = number
                    return PlannedFile(original: original, stagedName: name)
                }
            }
        }
    }

    /// Validates and creates only the staged copies needed by one active batch.
    /// Call this on the coordinator's I/O queue.
    func materialize(_ files: [PlannedFile]) -> [Result<URL, Error>] {
        files.map { file in
            Result {
                let lease = FileAccessLease(file.original)
                _ = try FileValidator.check(lease)
                return try withExtendedLifetime(lease) {
                    guard let name = file.stagedName else { return file.original }
                    return try stageDuplicate(file.original, named: name)
                }
            }
        }
    }

    /// Compatibility helper for the small staging unit tests. Product code plans
    /// once and materializes only the current batch.
    func prepare(_ originals: [URL]) -> [Result<URL, Error>] {
        materialize(plan(originals))
    }

    private func stageDuplicate(_ original: URL, named name: String) throws -> URL {
        let target = directory.appendingPathComponent(name)
        let lease = FileAccessLease(original)
        guard fm.fileExists(atPath: original.path) else { throw CocoaError(.fileNoSuchFile) }
        try withExtendedLifetime(lease) {
            // APFS clones share unchanged disk blocks; use a normal disk copy only
            // when the source filesystem cannot clone into our temporary directory.
            let cloned = original.withUnsafeFileSystemRepresentation { source in
                target.withUnsafeFileSystemRepresentation { destination in
                    guard let source, let destination else { return false }
                    return clonefile(source, destination, 0) == 0
                }
            }
            if !cloned { try fm.copyItem(at: original, to: target) }
        }
        return target
    }

    private static func nameKey(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
    }

    func release(_ urls: [URL]) {
        for url in urls where url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL {
            try? fm.removeItem(at: url)
        }
    }
}

enum SuperUploadProgressStage: Equatable, Sendable {
    /// The queue is validating lightweight local metadata before touching the
    /// ChatGPT composer. This gives very large clipboard selections visible,
    /// cancellable progress instead of appearing to freeze at zero.
    case checking
    /// A validated batch is being prepared, attached, or confirmed in chat.
    case uploading
}

struct SuperUploadProgress: Equatable, Sendable {
    let stage: SuperUploadProgressStage
    let processedFiles: Int
    let totalFiles: Int
}

/// Tracks the single ChatGPT conversation authorised by one Super Upload operation.
/// ChatGPT changes a new chat from `/` to `/c/<id>` asynchronously after the first send;
/// query/hash updates within that conversation are harmless, but another conversation is not.
struct SuperUploadRouteTracker: Sendable {
    private let scheme: String
    private let host: String
    private let port: Int?
    private let startingPath: String
    private(set) var conversationID: String?
    private(set) var isLocked: Bool

    init?(startingURL: URL) {
        guard let scheme = startingURL.scheme?.lowercased(),
              let host = startingURL.host?.lowercased() else { return nil }
        self.scheme = scheme
        self.host = host
        port = startingURL.port
        startingPath = Self.normalizedPath(startingURL.path)
        conversationID = Self.conversationID(in: startingURL)
        isLocked = conversationID != nil
    }

    mutating func observe(_ url: URL, maySettleConversation: Bool) {
        guard sameOrigin(url), !isLocked, maySettleConversation,
              let candidate = Self.conversationID(in: url) else { return }
        conversationID = candidate
    }

    mutating func allowsChange(from oldURL: URL?, to newURL: URL?,
                               maySettleConversation: Bool) -> Bool {
        guard let newURL, sameOrigin(newURL) else { return false }
        let newConversation = Self.conversationID(in: newURL)
        if isLocked, let conversationID {
            return newConversation == conversationID
        }
        if let newConversation {
            guard maySettleConversation else { return false }
            let oldConversation = oldURL.flatMap(Self.conversationID(in:))
            let oldPath = oldURL.map { Self.normalizedPath($0.path) } ?? startingPath
            guard oldConversation != nil || oldPath == startingPath else { return false }
            // A new ChatGPT conversation can briefly receive more than one optimistic URL.
            // It remains unsettled until the first assistant response is fully complete.
            conversationID = newConversation
            return true
        }
        return !isLocked && Self.normalizedPath(newURL.path) == startingPath
    }

    mutating func lockConversation(at url: URL) -> Bool {
        guard sameOrigin(url), let candidate = Self.conversationID(in: url) else { return false }
        if isLocked { return conversationID == candidate }
        conversationID = candidate
        isLocked = true
        return true
    }

    private func sameOrigin(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == host && url.port == port
    }

    private static func conversationID(in url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count == 2, parts[0] == "c", !parts[1].isEmpty {
            return String(parts[1])
        }
        // Project/custom-GPT pages use /g/<project-id>/c/<conversation-id>.
        // Treat the canonical /c/<id> form and this form as the same conversation,
        // while keeping all other paths unbound and fail-closed.
        if parts.count == 4, parts[0] == "g", !parts[1].isEmpty,
           parts[2] == "c", !parts[3].isEmpty {
            return String(parts[3])
        }
        return nil
    }

    private static func normalizedPath(_ value: String) -> String {
        var result = value.isEmpty ? "/" : value
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }
}

/// Runs the queue natively. JavaScript is limited to the small amount of DOM interaction
/// that only the embedded ChatGPT page can perform.
@MainActor
final class SuperUploadCoordinator {
    private struct Candidate {
        let plannedFile: SuperUploadFileStaging.PlannedFile
        let extensionName: String
        let mime: String

        var typeKey: String { "\(extensionName.lowercased())\u{1f}\(mime.lowercased())" }
        var sourceURL: URL { plannedFile.original }
    }

    private enum SkipReason {
        case unsupported
        case unavailable
        case directory
        case symbolicLink
        case cloudPlaceholder
        case pageUnsupported
        case clipboardRepresentation
        case rejectedByPage(String)

        var english: String {
            switch self {
            case .unsupported: return "not a regular local file"
            case .unavailable: return "unavailable or unreadable"
            case .directory: return "folders and app bundles are not supported"
            case .symbolicLink: return "symbolic links are not followed"
            case .cloudPlaceholder: return "not downloaded from cloud storage"
            case .pageUnsupported: return "file type not supported by the current ChatGPT file control"
            case .clipboardRepresentation: return "unsupported clipboard file reference"
            case .rejectedByPage(let reason): return reason
            }
        }

        func promptText(_ language: SuperUploadLanguage) -> String {
            guard language == .swedish else { return english }
            switch self {
            case .unsupported: return "inte en vanlig lokal fil"
            case .unavailable: return "otillgänglig eller oläsbar"
            case .directory: return "mappar och app-paket stöds inte"
            case .symbolicLink: return "symboliska länkar följs inte"
            case .cloudPlaceholder: return "inte hämtad från molnlagringen"
            case .pageUnsupported: return "filtypen stöds inte av ChatGPTs aktuella filfält"
            case .clipboardRepresentation: return "filreferensen i urklippet stöds inte"
            case .rejectedByPage(let reason): return reason
            }
        }
    }

    private struct SkippedItem {
        let filename: String?
        let count: Int
        let reason: SkipReason

        func promptSummary(_ language: SuperUploadLanguage) -> String {
            if let filename { return "\(filename) — \(reason.promptText(language))" }
            switch language {
            case .english: return "\(count) clipboard items — \(reason.promptText(language))"
            case .swedish: return "\(count) objekt från urklippet — \(reason.promptText(language))"
            }
        }

        var recordName: String {
            filename ?? "Unsupported clipboard references (\(count))"
        }
    }

    private struct PreflightItem {
        let candidate: Candidate?
        let skipped: SkippedItem?
    }

    private struct TypeGroup {
        let key: String
        let extensionName: String
        let mime: String
        var count: Int
    }

    private enum Phase {
        case validating
        case beginning
        case handingOff
        case waitingForUpload
        case waitingInitialSubmission
        case waitingAutomaticSubmission
        case waitingForAssistant
    }

    private final class Session {
        let operationID: UUID
        let token: String
        let selectedCount: Int
        var candidates: [Candidate] = []
        var preflightFiles: [SuperUploadFileStaging.PlannedFile] = []
        var preflightOffset = 0
        var skipped: [SkippedItem]
        /// Keeps the attachment panel useful without allowing thousands of
        /// rejected clipboard entries to become thousands of native table rows.
        var recordedSkippedItems = 0
        var plan: SuperUploadPlan?
        var language: SuperUploadLanguage = .english
        var batchIndex = 0
        var phase: Phase = .validating
        var deadline = Date.distantFuture
        var handoffTime = Date.distantPast
        var expectedDraft = ""
        var baselineUserMessages = 0
        var baselineAssistantMessages = 0
        var baselineAlert = ""
        var readyChecks = 0
        var initialReadyNoticeShown = false
        var initialIntentTime: Date?
        var emptyDraftSince: Date?
        var automaticSubmitTime: Date?
        // Content-free telemetry retained only for the current automatic-send
        // confirmation. It makes a fail-closed stop actionable without keeping
        // chat text, filenames, paths, or DOM content in native state.
        var automaticMessageVerified = false
        var automaticUserTurnFound = false
        var automaticMatchedAttachments = 0
        var automaticExpectedAttachments = 0
        var automaticInteractiveCandidates = 0
        var automaticImageCandidates = 0
        var automaticAttachmentWrappers = 0
        var assistantReadyChecks = 0
        var sawAssistantBusy = false
        var assistantSignature = ""
        var assistantSignatureSince = Date.distantPast
        var submittedFiles = 0
        var runtimeSkippedCount = 0
        var skippedBatchCount = 0
        var hasSubmittedInitial = false
        var expectedFiles: [String] = []
        var routeTracker: SuperUploadRouteTracker?
        var staging: SuperUploadFileStaging?
        var activeStagedURLs: [URL] = []
        let automaticallySendFirstBatch: Bool
        var activity: NSObjectProtocol?
        // Store the availability-gated WebKit enum as its raw value so the
        // session remains loadable on macOS 13 as well.
        var previousInactiveSchedulingPolicyRawValue: Int?
        weak var webView: WKWebView?

        init(selection: FileSelection, automaticallySendFirstBatch: Bool) {
            operationID = selection.id
            token = UUID().uuidString
            selectedCount = selection.urls.count + selection.rejectedRepresentations
            skipped = selection.rejectedRepresentations > 0
                ? [SkippedItem(filename: nil, count: selection.rejectedRepresentations,
                               reason: .clipboardRepresentation)]
                : []
            self.automaticallySendFirstBatch = automaticallySendFirstBatch
        }

        deinit {
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            if #available(macOS 14.0, *), let raw = previousInactiveSchedulingPolicyRawValue,
               let webView, let policy = WKPreferences.InactiveSchedulingPolicy(rawValue: raw) {
                // Sessions are owned by the @MainActor coordinator. The explicit
                // assumeIsolated fallback keeps deinit cleanup actor-correct if a
                // cancelled session is released before normal stop() cleanup.
                MainActor.assumeIsolated {
                    webView.configuration.preferences.inactiveSchedulingPolicy = policy
                }
            }
        }
    }

    private let adapter: WebAdapter
    private let attachments: AttachmentCoordinator
    private let io = DispatchQueue(label: "ChatPretzel.super-upload-preflight", qos: .userInitiated)
    /// Validation never reads file bytes into app memory, but URL metadata may
    /// still involve cloud/Finder I/O. Keeping each hop small makes Cancel and
    /// the native event loop responsive for queues in the thousands.
    private static let preflightChunkSize = 64
    private static let maximumDetailedSkippedRecords = 100
    private var session: Session?
    var onNotice: ((String) -> Void)?
    /// Non-nil after the user's first send, or immediately after an explicitly
    /// authorised automatic start. While non-nil, the main window blocks interaction
    /// so the active conversation cannot be changed.
    var onProgress: ((SuperUploadProgress?) -> Void)?

    var isActive: Bool { session != nil }

    init(adapter: WebAdapter, attachments: AttachmentCoordinator) {
        self.adapter = adapter
        self.attachments = attachments
    }

    /// Super Upload is entered only from an explicit paste action containing more than ten items.
    @discardableResult
    func start(_ selection: FileSelection, automaticallySendFirstBatch: Bool = false) -> Bool {
        let selectedCount = selection.urls.count + selection.rejectedRepresentations
        guard selectedCount > SuperUploadPlan.defaultBatchSize else { return false }
        guard session == nil, !attachments.isBusy else {
            onNotice?("A file operation is already in progress. Wait for it to finish or cancel it first.")
            return true
        }
        guard !selection.urls.isEmpty else {
            onNotice?("None of the copied file references could be read. Nothing was sent.")
            return true
        }

        let current = Session(selection: selection, automaticallySendFirstBatch: automaticallySendFirstBatch)
        do { current.staging = try SuperUploadFileStaging(operationID: current.operationID) }
        catch {
            onNotice?("Super Upload could not create its temporary staging area. Nothing was sent.")
            return true
        }
        session = current
        // A confirmed Yes authorises the complete queue, including while the app is
        // inactive. Keep the lock from that boundary, before any asynchronous work.
        if automaticallySendFirstBatch {
            current.activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "ChatDesk Super Upload authorised queue")
            if #available(macOS 14.0, *) {
                if let webView = adapter.webView {
                    current.webView = webView
                    current.previousInactiveSchedulingPolicyRawValue = webView.configuration.preferences.inactiveSchedulingPolicy.rawValue
                    webView.configuration.preferences.inactiveSchedulingPolicy = .none
                }
            }
            onProgress?(SuperUploadProgress(stage: .checking,
                                             processedFiles: 0,
                                             totalFiles: current.selectedCount))
        }
        onNotice?("Super Upload is checking \(selectedCount) items locally. File contents are not loaded into app memory.")
        current.preflightFiles = current.staging!.plan(selection.urls)
        preflightNextChunk(current)
        return true
    }

    /// Preflight validation is deliberately streamed. The old eager implementation
    /// built a staging result and a second validation result for every selected URL
    /// before it returned to the main actor; 3,000 images could therefore retain
    /// several large arrays and thousands of duplicate staging copies at once.
    private func preflightNextChunk(_ current: Session) {
        guard session === current else { return }
        guard current.preflightOffset < current.preflightFiles.count else {
            begin(current)
            return
        }

        let start = current.preflightOffset
        let end = min(start + Self.preflightChunkSize, current.preflightFiles.count)
        let files = Array(current.preflightFiles[start..<end])
        let token = current.token
        io.async { [weak self] in
            let results = files.map { planned -> PreflightItem in
                do {
                    let lease = FileAccessLease(planned.original)
                    let file = try FileValidator.check(lease)
                    return PreflightItem(candidate: Candidate(
                        plannedFile: planned,
                        extensionName: file.url.pathExtension.lowercased(),
                        mime: file.mime.lowercased()), skipped: nil)
                } catch let error as FileValidationError {
                    return PreflightItem(candidate: nil, skipped: SkippedItem(
                        filename: planned.original.lastPathComponent, count: 1,
                        reason: Self.reason(for: error)))
                } catch {
                    return PreflightItem(candidate: nil, skipped: SkippedItem(
                        filename: planned.original.lastPathComponent, count: 1, reason: .unavailable))
                }
            }
            DispatchQueue.main.async {
                guard let self, let active = self.session, active.token == token else { return }
                for item in results {
                    if let candidate = item.candidate { active.candidates.append(candidate) }
                    if let skipped = item.skipped { active.skipped.append(skipped) }
                }
                active.preflightOffset = end
                if active.automaticallySendFirstBatch {
                    self.onProgress?(SuperUploadProgress(stage: .checking,
                                                         processedFiles: end,
                                                         totalFiles: active.selectedCount))
                }
                self.preflightNextChunk(active)
            }
        }
    }

    func cancel(reason: String = "Super Upload was cancelled. No additional batches were sent.") {
        stop(reason)
    }

    /// ChatGPT may report the automatic `/` -> `/c/<id>` route after the first reply, and may
    /// update query/hash state more than once. Keep the queue only inside that bound conversation.
    func allowsURLChange(from oldURL: URL?, to newURL: URL?) -> Bool {
        guard let current = session else { return false }
        if current.routeTracker == nil, let oldURL {
            current.routeTracker = SuperUploadRouteTracker(startingURL: oldURL)
        }
        let maySettle = current.routeTracker?.isLocked != true
            && (current.phase == .waitingInitialSubmission
                || current.phase == .waitingAutomaticSubmission
                || current.phase == .waitingForAssistant)
        return current.routeTracker?.allowsChange(
            from: oldURL, to: newURL, maySettleConversation: maySettle) == true
    }

    private func begin(_ current: Session) {
        guard session === current else { return }
        // Candidates retain the compact metadata needed for the remaining queue;
        // release the original planning list before querying the page so a large
        // selection is not represented twice for the whole upload.
        current.preflightFiles.removeAll(keepingCapacity: false)
        current.preflightOffset = 0
        guard !current.candidates.isEmpty else {
            recordSkipped(current)
            stop("Super Upload stopped because none of the selected items are readable local files. Nothing was sent.")
            return
        }

        let groups = typeGroups(current.candidates)
        let descriptors: [[String: Any]] = groups.map {
            ["extension": $0.extensionName, "mime": $0.mime, "count": $0.count]
        }
        current.phase = .beginning
        adapter.call("beginSuperUpload", arguments: [
            "token": current.token, "types": descriptors,
            "requireFocus": !current.automaticallySendFirstBatch
        ]) { [weak self, weak current] result in
            guard let self, let current, self.session === current else { return }
            guard case .success(let info) = result, Self.bool(info["ok"]),
                  let accepted = Self.boolArray(info["accepted"]),
                  accepted.count == groups.count else {
                if case .success(let info) = result, Self.bool(info["unsupportedAll"]) {
                    current.skipped.append(contentsOf: current.candidates.map {
                        SkippedItem(filename: $0.sourceURL.lastPathComponent, count: 1,
                                    reason: .pageUnsupported)
                    })
                }
                let message = Self.errorMessage(result) ?? "ChatGPT's file control could not start Super Upload."
                self.recordSkipped(current)
                self.stop(message)
                return
            }

            let acceptedKeys = Set(zip(groups, accepted).compactMap { $1 ? $0.key : nil })
            let rejectedByPage = current.candidates.filter { !acceptedKeys.contains($0.typeKey) }
            current.candidates.removeAll { !acceptedKeys.contains($0.typeKey) }
            current.skipped.append(contentsOf: rejectedByPage.map {
                SkippedItem(filename: $0.sourceURL.lastPathComponent, count: 1, reason: .pageUnsupported)
            })
            current.language = Self.detectLanguage(
                draft: info["draft"] as? String ?? "",
                chatSample: info["languageSample"] as? String ?? "",
                documentLanguage: info["documentLanguage"] as? String ?? "")
            if let href = info["href"] as? String, let url = URL(string: href) {
                current.routeTracker = SuperUploadRouteTracker(startingURL: url)
            }
            current.baselineAlert = Self.normalizedAlert(info["alertText"])
            self.recordSkipped(current)

            guard !current.candidates.isEmpty,
                  let plan = SuperUploadPlan(totalFiles: current.candidates.count) else {
                self.stop("Super Upload stopped because the current ChatGPT file control does not support any selected file type. Nothing was sent.")
                return
            }
            current.plan = plan
            if current.automaticallySendFirstBatch {
                self.onProgress?(SuperUploadProgress(stage: .uploading,
                                                     processedFiles: 0,
                                                     totalFiles: plan.totalFiles))
            }
            self.uploadBatch(current)
        }
    }

    private func uploadBatch(_ current: Session) {
        guard session === current, let plan = current.plan,
              plan.batches.indices.contains(current.batchIndex),
              let staging = current.staging else { return }
        let batch = plan.batches[current.batchIndex]
        let candidates = Array(current.candidates[(batch.start - 1)..<batch.end])
        current.expectedFiles = []
        current.activeStagedURLs = []
        current.phase = .handingOff
        onNotice?("Super Upload is preparing batch \(batch.number) of \(batch.totalBatches) (files \(batch.start)–\(batch.end) of \(batch.totalFiles)).")
        let token = current.token
        // Duplicate basename copies are materialised only for this one ten-file
        // handoff. A 3,000-file queue therefore has at most ten temporary copies
        // (and ten active security grants) instead of thousands.
        io.async { [weak self] in
            let materialized = staging.materialize(candidates.map(\.plannedFile))
            DispatchQueue.main.async {
                guard let self, let active = self.session, active.token == token else { return }
                var urls: [URL] = []
                var stagedURLs: [URL] = []
                for (candidate, result) in zip(candidates, materialized) {
                    switch result {
                    case .success(let url):
                        urls.append(url)
                        if url.deletingLastPathComponent().standardizedFileURL == staging.directory.standardizedFileURL {
                            stagedURLs.append(url)
                        }
                    case .failure(let error):
                        let reason: SkipReason
                        if let validationError = error as? FileValidationError {
                            reason = Self.reason(for: validationError)
                        } else {
                            reason = .unavailable
                        }
                        let item = SkippedItem(filename: candidate.sourceURL.lastPathComponent,
                                               count: 1, reason: reason)
                        active.skipped.append(item)
                        active.runtimeSkippedCount += 1
                        active.recordedSkippedItems += 1
                        self.attachments.recordSkipped(operationID: active.operationID,
                                                       filename: item.recordName,
                                                       detail: item.reason.english)
                        self.onNotice?("Super Upload skipped \(item.recordName): \(item.reason.english).")
                    }
                }
                active.activeStagedURLs = stagedURLs
                active.expectedFiles = urls.map(\.lastPathComponent)
                guard !urls.isEmpty else {
                    self.advancePastEmptyBatch(active)
                    return
                }
                let batchSelection = FileSelection(urls: urls, id: active.operationID)
                // Bind the exact filenames before opening the native picker. This
                // is an assertion boundary: native handoff is not evidence that
                // the page accepted the attachments.
                self.adapter.call("configureSuperUploadBatch", arguments: [
                    "token": active.token, "expectedFiles": active.expectedFiles
                ]) { [weak self, weak active] configured in
                    guard let self, let active, self.session === active else { return }
                    guard case .success(let info) = configured, Self.bool(info["ok"]) else {
                        self.stop(Self.errorMessage(configured) ?? "ChatGPT could not bind the current batch of filenames.")
                        return
                    }
                    self.attachments.start(batchSelection,
                                           requireFocus: active.batchIndex == 0 && !active.automaticallySendFirstBatch,
                                           superUploadToken: active.token) { [weak self, weak active] result in
                        guard let self, let active, self.session === active else { return }
                        switch result {
                        case .failure(let failure):
                            self.stop("Super Upload stopped: \(failure.localizedDescription)")
                        case .success:
                            active.phase = .waitingForUpload
                            active.deadline = Date().addingTimeInterval(5 * 60)
                            active.handoffTime = Date()
                            active.readyChecks = 0
                            self.pollForUpload(active)
                        }
                    }
                }
            }
        }
    }

    /// A file may disappear or lose access after the initial metadata check. Do
    /// not retry or overwrite anything: safely omit that empty batch and retain
    /// the fixed original batch boundaries for all following files.
    private func advancePastEmptyBatch(_ current: Session) {
        guard session === current, let plan = current.plan else { return }
        releaseStagedBatch(current)
        if current.batchIndex + 1 < plan.batches.count {
            current.skippedBatchCount += 1
            current.batchIndex += 1
            attachments.releaseSuperUploadBatch(operationID: current.operationID)
            uploadBatch(current)
        } else if current.hasSubmittedInitial {
            appendProgressMessage(current)
        } else {
            stop("None of the selected files could be attached. Nothing was sent.")
        }
    }

    private func pollForUpload(_ current: Session) {
        guard session === current else { return }
        guard Date() <= current.deadline else {
            stop("Super Upload stopped because ChatGPT did not finish preparing the current batch within five minutes.")
            return
        }
        readState(current) { [weak self, weak current] info in
            guard let self, let current, self.session === current else { return }
            if let error = Self.normalizedAttachmentError(info["attachmentError"]) {
                self.stop("Super Upload stopped: \(error). Check the current attachments before retrying.")
                return
            }
            if let failed = info["failedFiles"] as? [[String: Any]], !failed.isEmpty {
                self.handleAttachmentFailures(current, info: info) { [weak self, weak current] in
                    guard let self, let current, self.session === current else { return }
                    current.readyChecks = 0
                    if current.expectedFiles.isEmpty {
                        self.advancePastEmptyBatch(current)
                    } else {
                        self.later(current, after: 0.5) { [weak self, weak current] in
                            guard let self, let current else { return }
                            self.pollForUpload(current)
                        }
                    }
                }
                return
            }
            if !Self.bool(info["attachmentsReady"]) || Date().timeIntervalSince(current.handoffTime) < 1.5 {
                current.readyChecks = 0
            } else {
                current.readyChecks += 1
            }
            if current.readyChecks >= 3 {
                self.appendProgressMessage(current)
            } else {
                self.later(current, after: 0.5) { [weak self, weak current] in
                    guard let self, let current else { return }
                    self.pollForUpload(current)
                }
            }
        }
    }

    private func appendProgressMessage(_ current: Session) {
        guard session === current, let batch = effectiveBatch(current) else { return }
        let skipped = promptSkipSummaries(current)
        let message = SuperUploadMessageBuilder.message(
            for: batch, language: current.language, selectedCount: current.selectedCount,
            skippedCount: current.skipped.reduce(0) { $0 + $1.count }, skipped: skipped)
        let automatic = current.hasSubmittedInitial || current.automaticallySendFirstBatch
        adapter.call("appendSuperUploadMessage", arguments: [
            "token": current.token, "text": message, "automatic": automatic,
            "authorizeFirstSend": current.automaticallySendFirstBatch && !current.hasSubmittedInitial
        ]) { [weak self, weak current] result in
            guard let self, let current, self.session === current else { return }
            guard case .success(let info) = result, Self.bool(info["ok"]),
                  let draft = info["draft"] as? String,
                  let users = Self.integer(info["userMessages"]),
                  let assistants = Self.integer(info["assistantMessages"]) else {
                self.stop(Self.errorMessage(result) ?? "ChatGPT did not accept the Super Upload progress message.")
                return
            }
            current.expectedDraft = draft
            current.baselineUserMessages = users
            current.baselineAssistantMessages = assistants
            current.initialIntentTime = nil
            current.emptyDraftSince = nil
            current.automaticSubmitTime = nil
            current.automaticMessageVerified = false
            current.automaticUserTurnFound = false
            current.automaticMatchedAttachments = 0
            current.automaticExpectedAttachments = current.expectedFiles.count
            current.automaticInteractiveCandidates = 0
            current.automaticImageCandidates = 0
            current.automaticAttachmentWrappers = 0
            // The first batch is explicitly user-authorised. Do not expire its draft
            // while the user is away; automatic batches retain their finite guard.
            current.deadline = automatic ? Date().addingTimeInterval(2 * 60) : .distantFuture
            if automatic {
                current.phase = .waitingAutomaticSubmission
                self.pollAutomaticReady(current)
            } else {
                current.phase = .waitingInitialSubmission
                self.pollInitialSubmission(current)
            }
        }
    }

    /// Failed cards are handled before any progress text is appended.  The adapter's
    /// removal acknowledgement is required; a missing/ambiguous failure report is fatal.
    private func handleAttachmentFailures(_ current: Session, info: [String: Any],
                                          completion: @escaping () -> Void) {
        guard let raw = info["failedFiles"] else {
            if let error = Self.normalizedAttachmentError(info["attachmentError"]) {
                stop("Super Upload stopped after an ambiguous attachment failure: \(error)")
                return
            }
            completion(); return
        }
        let records: [[String: Any]]
        if let value = raw as? [[String: Any]] { records = value }
        else if let value = raw as? [Any] {
            records = value.compactMap { $0 as? [String: Any] }
            guard records.count == value.count else {
                stop(Self.normalizedAttachmentError(info["attachmentError"]) ?? "ChatGPT reported an ambiguous attachment failure. Inspect the current batch and retry manually.")
                return
            }
        } else {
            stop(Self.normalizedAttachmentError(info["attachmentError"]) ?? "ChatGPT reported an ambiguous attachment failure. Inspect the current batch and retry manually.")
            return
        }
        guard !records.isEmpty else { completion(); return }
        var names: [String] = []
        for record in records {
            guard let name = record["name"] as? String, !name.isEmpty,
                  let reason = record["reason"] as? String, !reason.isEmpty else {
                stop(Self.normalizedAttachmentError(info["attachmentError"]) ?? "ChatGPT reported an attachment failure without a unique filename and reason.")
                return
            }
            guard current.expectedFiles.filter({ $0 == name }).count == 1 else {
                stop("Super Upload stopped because ChatGPT reported an ambiguous attachment failure for \(name). Inspect the current batch and retry manually.")
                return
            }
            guard !names.contains(name) else {
                stop("Super Upload stopped because a failed filename was reported more than once.")
                return
            }
            names.append(name)
        }
        adapter.call("removeFailedSuperUploadFiles", arguments: ["token": current.token, "names": names]) { [weak self, weak current] result in
            guard let self, let current, self.session === current else { return }
            guard case .success(let value) = result, Self.bool(value["ok"]) else {
                self.stop(Self.errorMessage(result) ?? "Super Upload could not remove failed attachment cards safely.")
                return
            }
            current.expectedFiles.removeAll { names.contains($0) }
            current.runtimeSkippedCount += names.count
            for record in records {
                let name = record["name"] as! String, reason = record["reason"] as! String
                current.skipped.append(SkippedItem(filename: name, count: 1, reason: .rejectedByPage(reason)))
                self.attachments.recordSkipped(operationID: current.operationID, filename: name, detail: reason)
                self.onNotice?("Super Upload skipped \(name): \(reason).")
            }
            completion()
        }
    }

    /// Original batch boundaries stay fixed so skipping a file never loses or repeats a later URL.
    private func effectiveBatch(_ current: Session) -> SuperUploadBatchPlan? {
        guard let plan = current.plan, plan.batches.indices.contains(current.batchIndex) else { return nil }
        return SuperUploadBatchPlan(number: current.batchIndex + 1 - current.skippedBatchCount,
            totalBatches: plan.batches.count - current.skippedBatchCount,
            start: current.submittedFiles + 1, end: current.submittedFiles + current.expectedFiles.count,
            totalFiles: current.candidates.count - current.runtimeSkippedCount)
    }

    private func pollInitialSubmission(_ current: Session) {
        guard session === current, current.plan != nil else { return }
        // Waiting for the user's first Enter has no wall-clock expiration.
        readState(current) { [weak self, weak current] info in
            guard let self, let current, self.session === current else { return }
            let users = Self.integer(info["userMessages"]) ?? current.baselineUserMessages
            let intent = Self.bool(info["userIntent"])
            let userCountAdvanced = users > current.baselineUserMessages
            let submittedMessageVisible = Self.bool(info["lastUserMatchesExpected"])
            let attachmentsMatch = Self.bool(info["submittedAttachmentsMatch"])
            let draft = info["draft"] as? String ?? ""
            let draftIsEmpty = Self.normalizedMessageText(draft).isEmpty

            if userCountAdvanced && users > current.baselineUserMessages + 1 {
                self.stop("Super Upload stopped because more than one message was sent while the first batch was pending.")
                return
            }
            if intent {
                if current.initialIntentTime == nil { current.initialIntentTime = Date() }
                if let expected = info["expectedDraft"] as? String, !expected.isEmpty { current.expectedDraft = expected }
                if Self.initialSubmissionConfirmed(
                    users: users,
                    baselineUsers: current.baselineUserMessages,
                    userIntent: intent,
                    lastUserMatchesExpected: submittedMessageVisible,
                    submittedAttachmentsMatch: attachmentsMatch) {
                    current.hasSubmittedInitial = true
                    self.batchWasSubmitted(current)
                    return
                }
                if Date().timeIntervalSince(current.initialIntentTime ?? Date()) >= 60 {
                    let count = Self.integer(info["submittedAttachmentCount"]) ?? 0
                    let controls = Self.integer(info["submittedInteractiveCandidateCount"]) ?? 0
                    let images = Self.integer(info["submittedImageCandidateCount"]) ?? 0
                    let wrappers = Self.integer(info["submittedAttachmentWrapperCandidateCount"]) ?? 0
                    let missing = (info["unconfirmedFiles"] as? [String] ?? []).prefix(10).joined(separator: ", ")
                    self.stop("Super Upload could not confirm the first sent batch within 60 seconds (message: \(submittedMessageVisible ? "confirmed" : "unconfirmed"), attachment cards: \(count)/\(current.expectedFiles.count), live controls/images/wrappers: \(controls)/\(images)/\(wrappers)).\(missing.isEmpty ? "" : " Unconfirmed: \(missing).")")
                    return
                }
            }
            if !intent { current.emptyDraftSince = draftIsEmpty ? (current.emptyDraftSince ?? Date()) : nil }

            if !current.initialReadyNoticeShown, Self.bool(info["sendReady"]),
               !Self.bool(info["uploading"]), !Self.bool(info["busy"]) {
                current.initialReadyNoticeShown = true
                guard let first = self.effectiveBatch(current) else { return }
                self.onNotice?("Super Upload: files \(first.start)–\(first.end) of \(first.totalFiles) are ready. Press Enter once; all remaining batches will be sent automatically.")
            }
            self.later(current, after: 0.5) { [weak self, weak current] in
                guard let self, let current else { return }
                self.pollInitialSubmission(current)
            }
        }
    }

    private func pollAutomaticReady(_ current: Session) {
        guard session === current else { return }
        guard Date() <= current.deadline else {
            stop("Super Upload stopped because ChatGPT was not ready for the next automatic batch.")
            return
        }
        readState(current) { [weak self, weak current] info in
            guard let self, let current, self.session === current else { return }
            let draft = info["draft"] as? String ?? ""
            let draftMatches = Self.bool(info["draftMatchesExpected"])
                || Self.normalizedMessageText(draft) == Self.normalizedMessageText(current.expectedDraft)
            guard draftMatches else {
                self.stop("Super Upload stopped because the automatic progress message changed. Nothing was overwritten.")
                return
            }
            guard Self.bool(info["sendReady"]), Self.bool(info["attachmentsReady"]),
                  !Self.bool(info["uploading"]), !Self.bool(info["busy"]) else {
                self.later(current, after: 0.5) { [weak self, weak current] in
                    guard let self, let current else { return }
                    self.pollAutomaticReady(current)
                }
                return
            }
            self.adapter.call("submitSuperUpload", arguments: [
                "token": current.token, "expectedDraft": current.expectedDraft
            ]) { [weak self, weak current] result in
                guard let self, let current, self.session === current else { return }
                guard case .success(let value) = result, Self.bool(value["ok"]) else {
                    self.stop(Self.errorMessage(result) ?? "ChatGPT did not accept the automatic send action.")
                    return
                }
                current.automaticSubmitTime = Date()
                current.deadline = Date().addingTimeInterval(60)
                self.pollAutomaticSubmission(current)
            }
        }
    }

    private func pollAutomaticSubmission(_ current: Session) {
        guard session === current else { return }
        guard Date() <= current.deadline else {
            let batch = effectiveBatch(current)?.number ?? current.batchIndex + 1
            let message = current.automaticMessageVerified ? "verified" : "not verified"
            let turn = current.automaticUserTurnFound ? "found" : "not found"
            let expected = max(current.automaticExpectedAttachments, current.expectedFiles.count)
            stop("Super Upload stopped because ChatGPT did not confirm the automatic message in the conversation (batch \(batch); message \(message); user turn \(turn); attachments \(current.automaticMatchedAttachments) of \(expected) verified; live controls/images/wrappers \(current.automaticInteractiveCandidates)/\(current.automaticImageCandidates)/\(current.automaticAttachmentWrappers)).")
            return
        }
        readState(current) { [weak self, weak current] info in
            guard let self, let current, self.session === current else { return }
            let users = Self.integer(info["userMessages"]) ?? current.baselineUserMessages
            let messageVisible = Self.bool(info["lastUserMatchesExpected"])
            let attachmentsMatch = Self.bool(info["submittedAttachmentsMatch"])
            current.automaticMessageVerified = messageVisible
            current.automaticUserTurnFound = Self.bool(info["submittedUserTurnFound"])
            current.automaticMatchedAttachments = Self.integer(info["submittedAttachmentMatchedCount"]) ?? 0
            current.automaticExpectedAttachments = Self.integer(info["submittedAttachmentExpectedCount"])
                ?? current.expectedFiles.count
            current.automaticInteractiveCandidates = Self.integer(info["submittedInteractiveCandidateCount"]) ?? 0
            current.automaticImageCandidates = Self.integer(info["submittedImageCandidateCount"]) ?? 0
            current.automaticAttachmentWrappers = Self.integer(info["submittedAttachmentWrapperCandidateCount"]) ?? 0
            if users > current.baselineUserMessages + 1 {
                    self.stop("Super Upload stopped because another message was sent while the automatic batch was pending.")
                    return
            }
            if messageVisible && attachmentsMatch {
                self.batchWasSubmitted(current)
                return
            }
            self.later(current, after: 0.5) { [weak self, weak current] in
                guard let self, let current else { return }
                self.pollAutomaticSubmission(current)
            }
        }
    }

    private func batchWasSubmitted(_ current: Session) {
        guard session === current, let batch = effectiveBatch(current) else { return }
        current.submittedFiles = batch.sentAfterBatch
        if !current.hasSubmittedInitial { current.hasSubmittedInitial = true }
        onProgress?(SuperUploadProgress(stage: .uploading,
                                        processedFiles: batch.sentAfterBatch,
                                        totalFiles: batch.totalFiles))
        // The reply gate exists solely to protect the *next* automatic batch.
        // Once the final user message and all of its attachment cards have been
        // confirmed, there is no subsequent batch to protect. Keeping the
        // frosted overlay until a potentially slow final answer arrives makes a
        // completed 41-file queue look stuck and needlessly locks the app.
        if batch.isLast {
            finish(current, finalResponseMayStillBeProcessing: true)
            return
        }
        current.phase = .waitingForAssistant
        current.assistantReadyChecks = 0
        current.sawAssistantBusy = false
        current.assistantSignature = ""
        current.assistantSignatureSince = Date.distantPast
        current.deadline = Date().addingTimeInterval(10 * 60)
        if !batch.isLast {
            onNotice?("Super Upload sent \(batch.sentAfterBatch) of \(batch.totalFiles) files. Waiting for ChatGPT before batch \(batch.number + 1) of \(batch.totalBatches).")
        } else {
            onNotice?("Super Upload sent \(batch.sentAfterBatch) of \(batch.totalFiles) files. Waiting for ChatGPT to finish responding.")
        }
        pollForAssistant(current)
    }

    private func pollForAssistant(_ current: Session) {
        guard session === current else { return }
        guard Date() <= current.deadline else {
            stop("Super Upload stopped because ChatGPT did not finish responding within ten minutes.")
            return
        }
        readState(current) { [weak self, weak current] info in
            guard let self, let current, self.session === current else { return }
            let users = Self.integer(info["userMessages"]) ?? (current.baselineUserMessages + 1)
            guard users <= current.baselineUserMessages + 1 else {
                self.stop("Super Upload stopped because another message was sent while it was waiting for ChatGPT.")
                return
            }
            let assistants = Self.integer(info["assistantMessages"]) ?? current.baselineAssistantMessages
            let responseBusy = Self.bool(info["busy"])
            if responseBusy { current.sawAssistantBusy = true }
            let responseExists = assistants > current.baselineAssistantMessages
                || Self.bool(info["assistantResponseObserved"])
            let responseComplete = Self.bool(info["assistantResponseComplete"])
            let signature = (info["assistantSignature"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if responseExists && responseComplete && !responseBusy && !signature.isEmpty {
                if signature != current.assistantSignature {
                    current.assistantSignature = signature
                    current.assistantSignatureSince = Date()
                    current.assistantReadyChecks = 1
                } else {
                    current.assistantReadyChecks += 1
                }
            } else {
                current.assistantReadyChecks = 0
                current.assistantSignature = ""
                current.assistantSignatureSince = Date.distantPast
            }
            if current.assistantReadyChecks >= 3,
               Date().timeIntervalSince(current.assistantSignatureSince) >= 1.5 {
                if current.plan?.batches[current.batchIndex].isLast == true {
                    self.finish(current)
                    return
                }
                guard let href = info["href"] as? String, let route = URL(string: href),
                      self.adapter.webView?.url?.absoluteString == href else {
                    self.later(current, after: 0.5) { [weak self, weak current] in
                        guard let self, let current else { return }
                        self.pollForAssistant(current)
                    }
                    return
                }
                let routeIsLocked: Bool
                if current.routeTracker != nil {
                    routeIsLocked = current.routeTracker?.lockConversation(at: route) == true
                } else {
                    routeIsLocked = self.adapter.policy.isFixture(route)
                }
                guard routeIsLocked else {
                    self.stop("Super Upload stopped because the active ChatGPT conversation could not be verified.")
                    return
                }
                self.attachments.releaseSuperUploadBatch(operationID: current.operationID)
                self.releaseStagedBatch(current)
                current.batchIndex += 1
                self.uploadBatch(current)
                return
            }
            self.later(current, after: 1) { [weak self, weak current] in
                guard let self, let current else { return }
                self.pollForAssistant(current)
            }
        }
    }

    private func readState(_ current: Session, completion: @escaping ([String: Any]) -> Void) {
        // A queued WebKit callback used to leave the frosted interaction lock
        // visible forever under a heavily loaded image conversation.  A timeout
        // fails closed here: it unlocks and sends no unverified next batch.
        adapter.call("superUploadState", arguments: ["token": current.token], timeout: 15) { [weak self, weak current] result in
            guard let self, let current, self.session === current else { return }
            guard case .success(let info) = result, Self.bool(info["ok"]) else {
                self.stop(Self.errorMessage(result) ?? "The Super Upload session is no longer attached to this ChatGPT page.")
                return
            }
            if let href = info["href"] as? String, let url = URL(string: href) {
                let maySettle = current.routeTracker?.isLocked != true
                    && (current.phase == .waitingInitialSubmission
                        || current.phase == .waitingAutomaticSubmission
                        || current.phase == .waitingForAssistant)
                current.routeTracker?.observe(url, maySettleConversation: maySettle)
            }
            let alert = Self.normalizedAlert(info["alertText"])
            if !alert.isEmpty && alert != current.baselineAlert {
                self.stop("Super Upload stopped after ChatGPT reported an error: \(alert)")
                return
            }
            if current.phase != .waitingForUpload,
               let failure = Self.normalizedAttachmentError(info["attachmentError"]) {
                self.stop("Super Upload stopped: \(failure). Check the current attachments before retrying.")
                return
            }
            if current.phase == .waitingInitialSubmission || current.phase == .waitingAutomaticSubmission,
               let failures = info["failedFiles"] as? [[String: Any]], !failures.isEmpty {
                self.stop("An attachment failed after the message was prepared. Check or remove the failed file before retrying; no further batches were sent.")
                return
            }
            completion(info)
        }
    }

    private func finish(_ current: Session, finalResponseMayStillBeProcessing: Bool = false) {
        guard session === current, let plan = current.plan else { return }
        releaseExecutionResources(current)
        session = nil
        onProgress?(nil)
        adapter.call("endSuperUpload", arguments: ["token": current.token]) { _ in }
        attachments.completeSuperUpload(operationID: current.operationID)
        retireStaging(current)
        let skipped = current.skipped.reduce(0) { $0 + $1.count }
        let suffix = skipped > 0 ? " \(skipped) unsupported or unreadable items were skipped and reported in the conversation." : ""
        let finalResponse = finalResponseMayStillBeProcessing
            ? " ChatGPT may still be processing the final batch."
            : ""
        onNotice?("Super Upload finished: \(current.submittedFiles) files were confirmed in the conversation across \(plan.batches.count - current.skippedBatchCount) batches.\(suffix)\(finalResponse)")
    }

    private func stop(_ reason: String) {
        guard let current = session else { return }
        releaseExecutionResources(current)
        session = nil
        onProgress?(nil)
        adapter.call("endSuperUpload", arguments: ["token": current.token]) { _ in }
        attachments.cancelSuperUpload(operationID: current.operationID, reason: reason)
        retireStaging(current)
        let progress = current.submittedFiles > 0 ? " \(current.submittedFiles) files were confirmed in the conversation. Check the last message before retrying; an unconfirmed batch may also have been sent." : ""
        onNotice?("\(reason)\(progress) No additional batches will be sent.")
    }

    private func releaseExecutionResources(_ current: Session) {
        if let activity = current.activity {
            ProcessInfo.processInfo.endActivity(activity)
            current.activity = nil
        }
        if #available(macOS 14.0, *), let previous = current.previousInactiveSchedulingPolicyRawValue,
           let webView = adapter.webView {
            if let policy = WKPreferences.InactiveSchedulingPolicy(rawValue: previous) {
                webView.configuration.preferences.inactiveSchedulingPolicy = policy
            }
            current.previousInactiveSchedulingPolicyRawValue = nil
        }
    }

    private func releaseStagedBatch(_ current: Session) {
        guard let staging = current.staging, !current.activeStagedURLs.isEmpty else { return }
        let urls = current.activeStagedURLs
        current.activeStagedURLs.removeAll(keepingCapacity: true)
        io.async { staging.release(urls) }
    }

    private func retireStaging(_ current: Session) {
        guard let staging = current.staging else { return }
        let urls = current.activeStagedURLs
        current.activeStagedURLs.removeAll(keepingCapacity: false)
        current.staging = nil
        // Serialize the final batch cleanup behind any in-flight validation/copy
        // work; never block the UI or leave duplicate-name copies behind.
        io.async {
            staging.release(urls)
            withExtendedLifetime(staging) {}
        }
    }

    private func recordSkipped(_ current: Session) {
        guard current.recordedSkippedItems < current.skipped.count else { return }
        let pending = current.skipped.dropFirst(current.recordedSkippedItems)
        let detailedCapacity = max(0, Self.maximumDetailedSkippedRecords - current.recordedSkippedItems)
        for item in pending.prefix(detailedCapacity) {
            attachments.recordSkipped(operationID: current.operationID,
                                      filename: item.recordName,
                                      detail: item.reason.english)
        }
        let hidden = pending.dropFirst(detailedCapacity)
        if !hidden.isEmpty {
            let hiddenCount = hidden.reduce(0) { $0 + $1.count }
            attachments.recordSkipped(operationID: current.operationID,
                                      filename: "Additional skipped files",
                                      detail: "\(hiddenCount) additional items were skipped; see the Super Upload message for the summary.")
        }
        current.recordedSkippedItems = current.skipped.count
    }

    private func promptSkipSummaries(_ current: Session) -> [String] {
        let total = current.skipped.reduce(0) { $0 + $1.count }
        // A large Finder/clipboard selection can contain thousands of stale
        // references. Listing their long generated filenames in the first ChatGPT
        // message makes the page collapse that message and is both noisy and a
        // poor privacy default. Preserve a small detailed list for ordinary
        // cases, but use a compact reason summary for large groups.
        if total > 50 {
            var byReason: [String: Int] = [:]
            for item in current.skipped {
                let reason = item.reason.promptText(current.language)
                byReason[reason, default: 0] += item.count
            }
            return byReason
                .sorted { lhs, rhs in
                    lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
                }
                .prefix(3)
                .map { "\($0.value) \($0.key)" }
        }

        let shown = Array(current.skipped.prefix(3))
        var values = shown.map { $0.promptSummary(current.language) }
        let shownCount = shown.reduce(0) { $0 + $1.count }
        let remaining = total - shownCount
        if remaining > 0 {
            values.append(current.language == .swedish
                          ? "och ytterligare \(remaining) utelämnade objekt"
                          : "and \(remaining) more skipped items")
        }
        return values
    }

    private func typeGroups(_ candidates: [Candidate]) -> [TypeGroup] {
        var groups: [String: TypeGroup] = [:]
        for candidate in candidates {
            if var existing = groups[candidate.typeKey] {
                existing.count += 1
                groups[candidate.typeKey] = existing
            } else {
                groups[candidate.typeKey] = TypeGroup(
                    key: candidate.typeKey, extensionName: candidate.extensionName,
                    mime: candidate.mime, count: 1)
            }
        }
        return groups.values.sorted { $0.key < $1.key }
    }

    private func later(_ current: Session, after delay: TimeInterval,
                       action: @escaping () -> Void) {
        let scheduledAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak current] in
            guard let self, let current, self.session === current else { return }
            let suspended = Self.suspendedInterval(elapsed: Date().timeIntervalSince(scheduledAt), scheduledDelay: delay)
            if suspended > 0 {
                // A suspended main loop cannot observe upload progress. Preserve the
                // remaining timeout, then let the normal page/evidence checks run.
                // This neither reloads the page nor assumes a send succeeded.
                if current.deadline != .distantFuture { current.deadline.addTimeInterval(suspended) }
                current.initialIntentTime = current.initialIntentTime?.addingTimeInterval(suspended)
                current.automaticSubmitTime = current.automaticSubmitTime?.addingTimeInterval(suspended)
                current.readyChecks = 0
                current.assistantReadyChecks = 0
                current.assistantSignatureSince = Date()
            }
            action()
        }
    }

    static func suspendedInterval(elapsed: TimeInterval, scheduledDelay: TimeInterval) -> TimeInterval {
        let gap = elapsed - scheduledDelay
        return gap.isFinite && gap > 30 ? gap : 0
    }

    nonisolated private static func reason(for error: FileValidationError) -> SkipReason {
        switch error {
        case .unsupported: return .unsupported
        case .unavailable: return .unavailable
        case .directory: return .directory
        case .symbolicLink: return .symbolicLink
        case .cloudPlaceholder: return .cloudPlaceholder
        }
    }

    private static func detectLanguage(draft: String, chatSample: String,
                                       documentLanguage: String) -> SuperUploadLanguage {
        for sample in [draft, chatSample] {
            let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3 else { continue }
            if let code = NLLanguageRecognizer.dominantLanguage(for: trimmed)?.rawValue.lowercased() {
                if code == "sv" { return .swedish }
                return .english
            }
        }
        for identifier in Locale.preferredLanguages + [documentLanguage] {
            let code = identifier.lowercased()
            if code == "sv" || code.hasPrefix("sv-") || code.hasPrefix("sv_") { return .swedish }
            if !code.isEmpty { return .english }
        }
        return .english
    }

    private static func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        return (value as? NSNumber)?.boolValue ?? false
    }

    private static func boolArray(_ value: Any?) -> [Bool]? {
        if let value = value as? [Bool] { return value }
        guard let values = value as? [Any] else { return nil }
        return values.map { bool($0) }
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }

    /// Exact evidence for the one user-authorised first send.  A count advance by
    /// itself is insufficient because it could be an unrelated user message.
    static func initialSubmissionConfirmed(users: Int,
                                           baselineUsers: Int,
                                           userIntent: Bool,
                                           lastUserMatchesExpected: Bool,
                                           submittedAttachmentsMatch: Bool) -> Bool {
        // Message counts are not reliable in virtualized long conversations.  The
        // bounded count check still rejects a clearly additional message, while the
        // intent signal prevents an old identical message from being re-used after
        // an idle/sleep timeout.
        userIntent && users <= baselineUsers + 1 && lastUserMatchesExpected && submittedAttachmentsMatch
    }

    private static func normalizedAlert(_ value: Any?) -> String {
        (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedAttachmentError(_ value: Any?) -> String? {
        let text = (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func normalizedMessageText(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func errorMessage(_ result: Result<[String: Any], Error>) -> String? {
        switch result {
        case .success(let info): return info["error"] as? String
        case .failure(let error): return error.localizedDescription
        }
    }
}
