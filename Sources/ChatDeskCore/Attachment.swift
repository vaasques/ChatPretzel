import Foundation

public enum AttachmentState: String, Codable, CaseIterable, Sendable {
    case identified, checking, waitingForWebKit, handedToWebKit, userConfirmed, failed, cancelled, unknown
    public var label: String {
        switch self {
        case .identified: return "Identified locally"
        case .checking: return "Checking file"
        case .waitingForWebKit: return "Waiting for WebKit"
        case .handedToWebKit: return "Handed over – upload not verified"
        case .userConfirmed: return "Confirmed by user"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled before handoff"
        case .unknown: return "Final status unknown"
        }
    }
    public func allows(_ next: AttachmentState) -> Bool {
        switch (self, next) {
        case (.identified, .checking), (.identified, .cancelled),
             (.checking, .waitingForWebKit), (.checking, .failed), (.checking, .cancelled),
             (.waitingForWebKit, .handedToWebKit), (.waitingForWebKit, .failed),
             (.waitingForWebKit, .cancelled), (.waitingForWebKit, .unknown),
             (.handedToWebKit, .userConfirmed), (.handedToWebKit, .unknown),
             (.handedToWebKit, .failed), (.unknown, .userConfirmed), (.unknown, .failed): return true
        default: return self == next
        }
    }
}
public struct AttachmentRecord: Identifiable, Sendable {
    public let id: UUID
    public let operationID: UUID
    public let filename: String
    public var byteCount: Int64?
    public private(set) var state: AttachmentState
    public var detail: String
    public init(id: UUID = UUID(), operationID: UUID, filename: String,
                byteCount: Int64? = nil, state: AttachmentState = .identified, detail: String = "") {
        self.id = id; self.operationID = operationID; self.filename = filename
        self.byteCount = byteCount; self.state = state; self.detail = detail
    }
    @discardableResult public mutating func transition(to next: AttachmentState, detail: String = "") -> Bool {
        guard state.allows(next) else { return false }
        state = next; self.detail = detail; return true
    }
}
public struct FileSelection: Sendable {
    public let id: UUID
    public let urls: [URL]
    public let rejectedRepresentations: Int
    public init(urls: [URL], rejectedRepresentations: Int = 0, id: UUID = UUID()) {
        self.id = id; self.rejectedRepresentations = rejectedRepresentations
        var seen = Set<String>()
        // Deduplicate file identity inside ONE operation, never by basename.
        self.urls = urls.filter { $0.isFileURL }.filter {
            seen.insert($0.standardizedFileURL.absoluteString).inserted
        }
    }
}
public enum FilePolicy {
    /// Only decode a typed public.file-url representation, NOT plain clipboard text.
    public static func url(fromTypedRepresentation string: String) -> URL? {
        guard let url = URL(string: string), url.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost", !url.path.isEmpty else { return nil }
        return url
    }
    public static func safeDownloadName(_ suggested: String) -> String {
        let last = suggested.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? "Download"
        let cleaned = last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" }
        let name = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." { return "Download" }
        return String(name.prefix(180))
    }
}
