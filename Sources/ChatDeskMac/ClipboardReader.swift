import AppKit
import UniformTypeIdentifiers
import ChatDeskCore

public enum ClipboardReadResult {
    case files(FileSelection)
    case mailRichText(data: Data, changeCount: Int)
    case useSystemPaste
    case unsupported(String)
}

/// Does not monitor the clipboard. Call only inside an explicit native paste/drop action.
public enum ClipboardReader {
    private static let flatRTFD = NSPasteboard.PasteboardType("com.apple.flat-rtfd")
    private static let maximumRichTextBytes = 256 * 1024 * 1024

    public static func read(_ pasteboard: NSPasteboard) -> ClipboardReadResult {
        let items = pasteboard.pasteboardItems ?? []
        let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let hasTypedFile = items.contains { $0.types.contains(.fileURL) }
        let hasLegacyFiles = pasteboard.types?.contains(legacyType) == true

        guard hasTypedFile || hasLegacyFiles else {
            // Mail copies a selected attachment inside flat RTFD. Keep this typed representation
            // separate from ordinary text, screenshots, and raw images, which remain on WebKit's
            // normal paste path. Parsing and disk I/O happen later on a background queue.
            if items.count == 1, items[0].types.contains(flatRTFD),
               let data = items[0].data(forType: flatRTFD) {
                guard data.count <= maximumRichTextBytes else {
                    return .unsupported("The copied Mail attachment is too large to stage safely. Save it to Finder and attach the saved file instead.")
                }
                return .mailRichText(data: data, changeCount: pasteboard.changeCount)
            }
            let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)
            let hasPromises = items.contains { item in item.types.contains { promiseTypes.contains($0.rawValue) } }
            if hasPromises {
                return .unsupported("This source supplied a promised file instead of a copied attachment. Save or drag it to Finder, then paste the saved file.")
            }
            return .useSystemPaste
        }

        // Retain native NSURL objects returned by the pasteboard. Do not turn plain path text into grants.
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        let nativeURLs = objects.compactMap { ($0 as? NSURL).map { $0 as URL } }
        var urls: [URL] = []
        var rejected = 0
        for item in items where item.types.contains(.fileURL) {
            guard let representation = item.string(forType: .fileURL),
                  let parsed = FilePolicy.url(fromTypedRepresentation: representation) else { rejected += 1; continue }
            urls.append(nativeURLs.first(where: { $0.standardizedFileURL == parsed.standardizedFileURL }) ?? parsed)
        }
        if !hasTypedFile, hasLegacyFiles,
           let paths = pasteboard.propertyList(forType: legacyType) as? [String] {
            // This is an explicitly typed file-list format, not the plain-text pasteboard representation.
            for path in paths {
                guard path.hasPrefix("/") else { rejected += 1; continue }
                let url = URL(fileURLWithPath: path)
                urls.append(nativeURLs.first(where: { $0.standardizedFileURL == url.standardizedFileURL }) ?? url)
            }
        }
        guard !urls.isEmpty else {
            return .unsupported("The clipboard contains file references that could not be read. No file or filename text was sent.")
        }
        return .files(FileSelection(urls: urls, rejectedRepresentations: rejected))
    }
}

private struct EmbeddedAttachment {
    let suggestedName: String
    let data: Data
}

private enum MailAttachmentMaterializerError: LocalizedError {
    case busy
    case invalidRichText
    case invalidCount
    case unsupportedAttachment

    var errorDescription: String? {
        switch self {
        case .busy: return "Another Mail attachment paste is still being prepared. Please wait and try again."
        case .invalidRichText: return "The copied Mail content could not be read. No attachment was sent."
        case .invalidCount: return "Paste between 1 and 100 Mail attachments at a time. No attachment was sent."
        case .unsupportedAttachment: return "Mail included an attachment that was not a regular file. No partial selection was sent."
        }
    }
}

private func embeddedAttachments(in data: Data) throws -> [EmbeddedAttachment] {
    let attributed: NSAttributedString
    do {
        attributed = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil)
    } catch { throw MailAttachmentMaterializerError.invalidRichText }

    var attachments: [EmbeddedAttachment] = []
    var rejected = 0
    attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
        guard let attachment = value as? NSTextAttachment else { return }
        let wrapper = attachment.fileWrapper
        guard wrapper?.isDirectory != true,
              let bytes = wrapper?.regularFileContents ?? attachment.contents else { rejected += 1; return }
        var name = wrapper?.preferredFilename ?? wrapper?.filename ?? "Mail Attachment"
        if (name as NSString).pathExtension.isEmpty,
           let type = attachment.fileType,
           let extensionName = UTType(type)?.preferredFilenameExtension {
            name += ".\(extensionName)"
        }
        attachments.append(EmbeddedAttachment(suggestedName: name, data: bytes))
    }
    guard rejected == 0 else { throw MailAttachmentMaterializerError.unsupportedAttachment }
    guard attachments.count <= 100 else { throw MailAttachmentMaterializerError.invalidCount }
    return attachments
}

/// Extracts copied Mail attachments into an app-owned temporary directory. The files remain
/// available until the attachment operation is resolved or the app quits.
@MainActor
final class MailAttachmentMaterializer {
    private let fileManager: FileManager
    private let rootDirectory: URL
    private let queue = DispatchQueue(label: "ChatPretzel.mail-attachment-paste", qos: .userInitiated)
    private var stagedDirectories: [UUID: URL] = [:]
    private(set) var isReceiving = false

    init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? fileManager.temporaryDirectory
            .appendingPathComponent("ChatPretzel", isDirectory: true)
            .appendingPathComponent("MailAttachmentPaste", isDirectory: true)
        removeStaleDirectories()
    }

    func receive(_ data: Data, completion: @escaping (Result<FileSelection?, Error>) -> Void) {
        guard !isReceiving else { completion(.failure(MailAttachmentMaterializerError.busy)); return }
        let directory = rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
        } catch { completion(.failure(error)); return }

        isReceiving = true
        queue.async {
            let result = Result { () -> [URL] in
                let attachments = try embeddedAttachments(in: data)
                var usedNames = Set<String>()
                return try attachments.enumerated().map { index, attachment in
                    let safeName = FilePolicy.safeDownloadName(attachment.suggestedName)
                    let filename = uniqueFilename(safeName, index: index, used: &usedNames)
                    let url = directory.appendingPathComponent(filename, isDirectory: false)
                    try attachment.data.write(to: url, options: .atomic)
                    return url
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isReceiving = false
                switch result {
                case .failure(let error): self.remove(directory); completion(.failure(error))
                case .success(let urls):
                    guard !urls.isEmpty else { self.remove(directory); completion(.success(nil)); return }
                    let selection = FileSelection(urls: urls)
                    self.stagedDirectories[selection.id] = directory
                    completion(.success(selection))
                }
            }
        }
    }

    func release(_ operationID: UUID) {
        guard let directory = stagedDirectories.removeValue(forKey: operationID) else { return }
        remove(directory)
    }

    func cleanupAll() {
        let directories = Array(stagedDirectories.values)
        stagedDirectories.removeAll()
        directories.forEach(remove)
    }

    private func remove(_ directory: URL) {
        guard directory.deletingLastPathComponent().standardizedFileURL == rootDirectory.standardizedFileURL else { return }
        try? fileManager.removeItem(at: directory)
    }

    private func removeStaleDirectories() {
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true,
                                         attributes: [.posixPermissions: 0o700])
        guard let children = try? fileManager.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for child in children {
            let modified = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modified.map({ $0 < cutoff }) == true { remove(child) }
        }
    }
}

private func uniqueFilename(_ suggested: String, index: Int, used: inout Set<String>) -> String {
    let fallback = "Mail Attachment \(index + 1)"
    let initial = suggested.isEmpty ? fallback : suggested
    if used.insert(initial.lowercased()).inserted { return initial }
    let value = initial as NSString
    let stem = value.deletingPathExtension
    let suffix = value.pathExtension.isEmpty ? "" : ".\(value.pathExtension)"
    var number = 2
    while true {
        let candidate = "\(stem) \(number)\(suffix)"
        if used.insert(candidate.lowercased()).inserted { return candidate }
        number += 1
    }
}
