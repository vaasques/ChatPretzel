import Foundation
import UniformTypeIdentifiers

/// Keeps only a URL + OS access grant, never a copy of file bytes.
final class FileAccessLease {
    let url: URL
    let hasSecurityScope: Bool
    init(_ url: URL) {
        self.url = url
        hasSecurityScope = url.startAccessingSecurityScopedResource()
    }
    deinit { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
}
struct CheckedFile {
    let lease: FileAccessLease
    let size: Int64
    let modified: Date?
    let mime: String
    var url: URL { lease.url }
}
enum FileValidationError: Error {
    case unsupported, unavailable, directory, symbolicLink, cloudPlaceholder
    var message: String {
        switch self {
        case .unsupported: return "Ingen vanlig lokal fil."
        case .unavailable: return "Filen är inte tillgänglig eller saknar läsbehörighet."
        case .directory: return "Mappar och app-paket bifogas inte."
        case .symbolicLink: return "Symboliska länkar följs inte. Välj originalfilen."
        case .cloudPlaceholder: return "Molnfilen är inte hämtad lokalt. Hämta den i Finder och försök igen."
        }
    }
}
enum FileValidator {
    /// Run on a utility queue. Resource lookup/open may touch external storage.
    static func check(_ lease: FileAccessLease) throws -> CheckedFile {
        guard lease.url.isFileURL else { throw FileValidationError.unsupported }
        let values: URLResourceValues
        do {
            values = try lease.url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey,
                .isSymbolicLinkKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey,
                .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        } catch { throw FileValidationError.unavailable }
        guard values.isDirectory != true, values.isPackage != true else { throw FileValidationError.directory }
        guard values.isSymbolicLink != true else { throw FileValidationError.symbolicLink }
        if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded {
            throw FileValidationError.cloudPlaceholder
        }
        guard values.isRegularFile == true else { throw FileValidationError.unsupported }
        do { let handle = try FileHandle(forReadingFrom: lease.url); try handle.close() }
        catch { throw FileValidationError.unavailable }
        let mime = UTType(filenameExtension: lease.url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return CheckedFile(lease: lease, size: Int64(values.fileSize ?? 0),
                           modified: values.contentModificationDate, mime: mime)
    }
}
