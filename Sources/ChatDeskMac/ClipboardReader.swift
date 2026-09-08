import AppKit
import ChatDeskCore

public enum ClipboardReadResult {
    case files(FileSelection)
    case useSystemPaste
    case unsupported(String)
}

/// Does not monitor the clipboard. Call only inside an explicit native paste/drop action.
public enum ClipboardReader {
    public static func read(_ pasteboard: NSPasteboard) -> ClipboardReadResult {
        let items = pasteboard.pasteboardItems ?? []
        let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let hasTypedFile = items.contains { $0.types.contains(.fileURL) }
        let hasLegacyFiles = pasteboard.types?.contains(legacyType) == true
        let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)
        let promises = items.filter { item in item.types.contains { promiseTypes.contains($0.rawValue) } }.count

        guard hasTypedFile || hasLegacyFiles else {
            if promises > 0 { return .unsupported("File promises stöds inte ännu. Spara bilagorna i Finder först. Det är en reservväg, inte ett godkänt paste-test.") }
            // Text, screenshots and raw clipboard images stay on WebKit's normal paste path.
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
        rejected += promises
        guard !urls.isEmpty else { return .unsupported("Urklippet innehöll filreferenser som inte kunde läsas. Ingen fil eller filnamnstext skickades.") }
        return .files(FileSelection(urls: urls, rejectedRepresentations: rejected))
    }
}
