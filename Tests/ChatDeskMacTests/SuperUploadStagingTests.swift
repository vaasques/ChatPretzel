import XCTest
@testable import ChatDeskMac

final class SuperUploadStagingTests: XCTestCase {
    func testPlanningDuplicateNamesDoesNotCreateCopiesUntilTheirBatchIsMaterialized() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("staging-lazy-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let first = root.appendingPathComponent("report.pdf")
        let other = root.appendingPathComponent("other")
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        let second = other.appendingPathComponent("report.pdf")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let staging = try SuperUploadFileStaging(operationID: UUID())
        let planned = staging.plan([first, second])
        XCTAssertEqual(planned.map(\.uploadName), ["report.pdf", "report 2.pdf"])
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: staging.directory.path), [])

        let firstResult = try XCTUnwrap(staging.materialize([planned[0]]).first)
        XCTAssertEqual(try firstResult.get(), first)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: staging.directory.path), [])

        let secondResult = try XCTUnwrap(staging.materialize([planned[1]]).first)
        let stagedDuplicate = try secondResult.get()
        XCTAssertEqual(stagedDuplicate.lastPathComponent, "report 2.pdf")
        XCTAssertTrue(fm.fileExists(atPath: stagedDuplicate.path))
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
    }

    func testDuplicateNamesAreCopiedWithoutChangingOriginals() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("staging-test-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let other = root.appendingPathComponent("other")
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("report.pdf")
        let second = other.appendingPathComponent("REPORT.PDF")
        let reserved = root.appendingPathComponent("report 2.pdf")
        let unicode1 = root.appendingPathComponent("E\u{301}.txt")
        let unicode2 = other.appendingPathComponent("é.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        try Data("reserved".utf8).write(to: reserved)
        try Data("unicode-1".utf8).write(to: unicode1)
        try Data("unicode-2".utf8).write(to: unicode2)
        let firstBytes = try Data(contentsOf: first)
        let staging = try SuperUploadFileStaging(operationID: UUID())
        let results = staging.prepare([first, second, reserved, unicode1, unicode2,
                                       root.appendingPathComponent("missing.pdf")])
        let staged = results.compactMap { try? $0.get() }
        XCTAssertEqual(staged.count, 5)
        XCTAssertTrue(staged.contains { $0.lastPathComponent.lowercased() == "report 3.pdf" })
        XCTAssertTrue(staged.contains { $0.lastPathComponent.lowercased() == "é 2.txt" })
        XCTAssertEqual(try Data(contentsOf: first), firstBytes)
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
        XCTAssertTrue(staged.filter { $0.deletingLastPathComponent() == staging.directory }
            .allSatisfy { (try? Data(contentsOf: $0)) != nil })
    }

    func testReleaseAndDeinitRemoveOnlyStagedCopies() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("staging-cleanup-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let original = root.appendingPathComponent("a.txt")
        let duplicateDir = root.appendingPathComponent("other")
        try fm.createDirectory(at: duplicateDir, withIntermediateDirectories: true)
        let duplicate = duplicateDir.appendingPathComponent("a.txt")
        try Data("original".utf8).write(to: original)
        try Data("duplicate".utf8).write(to: duplicate)
        var staging: SuperUploadFileStaging? = try SuperUploadFileStaging(operationID: UUID())
        let prepared = staging!.prepare([original, duplicate]).compactMap { try? $0.get() }
        let copied = prepared[1]
        staging!.release([copied, original])
        XCTAssertFalse(fm.fileExists(atPath: copied.path))
        XCTAssertTrue(fm.fileExists(atPath: original.path))
        XCTAssertEqual(try Data(contentsOf: original), Data("original".utf8))
        let directory = staging!.directory
        staging = nil
        XCTAssertFalse(fm.fileExists(atPath: directory.path))
    }
}
