import Foundation
import UniformTypeIdentifiers
import os

/// Keeps only a URL + OS access grant, never a copy of file bytes.
final class FileAccessLease: @unchecked Sendable {
    let url: URL
    let hasSecurityScope: Bool
    init(_ url: URL) {
        self.url = url
        hasSecurityScope = url.startAccessingSecurityScopedResource()
    }
    deinit { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
}

/// One serial validation operation. Cancellation never waits for a cloud provider.
final class FileReadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var coordinator: NSFileCoordinator?

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func register(_ value: NSFileCoordinator) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        coordinator = value
        return true
    }
    func unregister() { lock.lock(); coordinator = nil; lock.unlock() }
    func cancel() {
        lock.lock(); cancelled = true; let active = coordinator; lock.unlock()
        active?.cancel()
    }
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
        case .unsupported: return "Not a regular local file."
        case .unavailable: return "The file is unavailable or does not have read permission."
        case .directory: return "Folders and app bundles cannot be attached."
        case .symbolicLink: return "Symbolic links are not followed. Choose the original file."
        case .cloudPlaceholder: return "The cloud provider did not make the file available within two minutes. Check its connection or download the file in Finder and try again."
        }
    }
}
enum FileValidator {
    private static let log = Logger(subsystem: "app.chatdesk.native", category: "FileAccess")
    private static func report(_ error: Error, stage: String, lease: FileAccessLease) {
        let cause = error as NSError
        // No filenames, paths, file content, or provider credentials in diagnostics.
        log.error("File validation failed at \(stage, privacy: .public): \(cause.domain, privacy: .public) \(cause.code); security scope \(lease.hasSecurityScope)")
    }
    /// Run on a utility queue. Preflight is metadata-only; downloading is limited
    /// to the active batch, not the thousands of files that may be queued behind it.
    static func check(_ lease: FileAccessLease, materialize: Bool = true,
                      cancellation: FileReadCancellation? = nil,
                      timeout: TimeInterval = 120) throws -> CheckedFile {
        guard lease.url.isFileURL else { throw FileValidationError.unsupported }
        guard cancellation?.isCancelled != true else { throw CocoaError(.userCancelled) }
        let initial = try metadata(lease.url, lease: lease)
        guard materialize else { return checked(lease, values: initial) }

        // A coordinated content read asks iCloud / File Provider to materialize
        // an evicted file. No forUploading snapshot, ZIP, or bytes-in-RAM copy.
        let coordinator = NSFileCoordinator(filePresenter: nil)
        guard cancellation?.register(coordinator) != false else { throw CocoaError(.userCancelled) }
        defer { cancellation?.unregister() }
        let deadline = DispatchWorkItem { [weak coordinator] in coordinator?.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel() }
        var coordinationError: NSError?
        var result: Result<CheckedFile, Error>?
        coordinator.coordinate(readingItemAt: lease.url, options: .withoutChanges,
                               error: &coordinationError) { url in
            result = Result {
                guard cancellation?.isCancelled != true else { throw CocoaError(.userCancelled) }
                // A rename while waiting requires a new explicit user selection.
                guard url.standardizedFileURL == lease.url.standardizedFileURL else {
                    throw FileValidationError.unavailable
                }
                let values = try metadata(url, lease: lease)
                do { let handle = try FileHandle(forReadingFrom: url); try handle.close() }
                catch { report(error, stage: "open", lease: lease); throw FileValidationError.unavailable }
                return checked(lease, values: values)
            }
        }
        guard cancellation?.isCancelled != true else { throw CocoaError(.userCancelled) }
        if let error = coordinationError {
            report(error, stage: "cloud coordination", lease: lease)
            if error.domain == NSCocoaErrorDomain, error.code == NSUserCancelledError {
                throw FileValidationError.cloudPlaceholder
            }
            throw FileValidationError.unavailable
        }
        guard let result else { throw FileValidationError.unavailable }
        return try result.get()
    }

    private static func metadata(_ url: URL, lease: FileAccessLease) throws -> URLResourceValues {
        let values: URLResourceValues
        do {
            // Optional iCloud-specific metadata must not prevent reading a local
            // file or a document from another File Provider.
            var freshURL = url
            freshURL.removeAllCachedResourceValues()
            values = try freshURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey,
                .isSymbolicLinkKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey])
        } catch { report(error, stage: "metadata", lease: lease); throw FileValidationError.unavailable }
        guard values.isDirectory != true, values.isPackage != true else { throw FileValidationError.directory }
        guard values.isSymbolicLink != true else { throw FileValidationError.symbolicLink }
        guard values.isRegularFile == true else { throw FileValidationError.unsupported }
        return values
    }
    private static func checked(_ lease: FileAccessLease, values: URLResourceValues) -> CheckedFile {
        let mime = UTType(filenameExtension: lease.url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return CheckedFile(lease: lease, size: Int64(values.fileSize ?? 0),
                           modified: values.contentModificationDate, mime: mime)
    }
}
