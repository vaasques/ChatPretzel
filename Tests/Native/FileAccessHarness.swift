import Foundation

/// Real Foundation I/O and coordinator tests; no XCTest, clipboard, or account.
@main
struct FileAccessHarness {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ChatPretzel-FileAccessTest-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("sample åäö.txt")
        let bytes = Data("Synthetic cloud coordination test".utf8)
        try bytes.write(to: file)
        let lease = FileAccessLease(file)
        let checked = try FileValidator.check(lease)
        let metadataOnly = try FileValidator.check(lease, materialize: false)
        let original = try Data(contentsOf: file)
        precondition(checked.size == Int64(bytes.count))
        precondition(metadataOnly.size == Int64(bytes.count))
        precondition(original == bytes, "Original must remain intact")

        let link = root.appendingPathComponent("link.txt")
        try fm.createSymbolicLink(at: link, withDestinationURL: file)
        do { _ = try FileValidator.check(FileAccessLease(link)); fatalError("Symlink accepted") }
        catch FileValidationError.symbolicLink { }
        do { _ = try FileValidator.check(FileAccessLease(root)); fatalError("Directory accepted") }
        catch FileValidationError.directory { }

        let stopped = FileReadCancellation(); stopped.cancel()
        do { _ = try FileValidator.check(lease, cancellation: stopped); fatalError("Cancelled read accepted") }
        catch let error as CocoaError { precondition(error.code == .userCancelled) }

        // A real coordinated writer keeps this file busy. The reader must stop
        // waiting without waiting for the writer (same mechanism as a provider).
        let locked = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let writerDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let writer = NSFileCoordinator(filePresenter: nil)
            var error: NSError?
            writer.coordinate(writingItemAt: file, options: .forReplacing, error: &error) { _ in
                locked.signal()
                _ = release.wait(timeout: .now() + 5)
            }
            writerDone.signal()
        }
        precondition(locked.wait(timeout: .now() + 2) == .success)
        defer { release.signal(); _ = writerDone.wait(timeout: .now() + 2) }
        let preflightStarted = Date()
        _ = try FileValidator.check(lease, materialize: false)
        precondition(Date().timeIntervalSince(preflightStarted) < 1,
                     "Queue preflight must not request a coordinated content read")
        let started = Date()
        do { _ = try FileValidator.check(lease, timeout: 0.05); fatalError("Timeout ignored") }
        catch FileValidationError.cloudPlaceholder { }
        precondition(Date().timeIntervalSince(started) < 1.5, "Provider wait was not bounded")
        let cancelled = FileReadCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { cancelled.cancel() }
        do { _ = try FileValidator.check(lease, cancellation: cancelled); fatalError("Cancel ignored") }
        catch let error as CocoaError { precondition(error.code == .userCancelled) }
        print("PASS: original bytes, metadata-only preflight, symlink/directory rejection, deadline and active cancellation")
    }
}
