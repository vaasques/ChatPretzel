import XCTest
import AppKit
@testable import ChatDeskMac
import ChatDeskCore

@MainActor
final class ClipboardReaderTests: XCTestCase {
    private func makePasteboard() -> NSPasteboard { NSPasteboard(name: NSPasteboard.Name("ChatDesk.tests.\(UUID().uuidString)")) }
    func testAllMixedFileURLsAreRead() {
        let board = makePasteboard(); defer { board.releaseGlobally() }
        let urls = ["pdf", "docx", "xlsx", "png", "jpg", "txt"].map { URL(fileURLWithPath: "/fixture/test åäö.\($0)") }
        board.writeObjects(urls.map { $0 as NSURL })
        guard case .files(let selection) = ClipboardReader.read(board) else { XCTFail("Expected typed file selection"); return }
        XCTAssertEqual(selection.urls, urls)
    }
    func testFileRepresentationWinsOverTextAndPreview() {
        let board = makePasteboard(); defer { board.releaseGlobally() }
        let url = URL(fileURLWithPath: "/fixture/document.docx")
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setString("document.docx", forType: .string)
        item.setData(Data([0,1,2,3]), forType: .png) // Deliberately unusable preview; must not be read as content.
        board.writeObjects([item])
        guard case .files(let selection) = ClipboardReader.read(board) else { XCTFail("Expected file URL"); return }
        XCTAssertEqual(selection.urls, [url])
    }
    func testPlainTextFileURLDoesNotGrantAccess() {
        let board = makePasteboard(); defer { board.releaseGlobally() }
        board.setString("file:///etc/passwd", forType: .string)
        guard case .useSystemPaste = ClipboardReader.read(board) else { XCTFail("Plain text is not a file grant"); return }
    }
    func testSameBasenameInTwoDirectoriesSurvives() {
        let board = makePasteboard(); defer { board.releaseGlobally() }
        board.writeObjects([NSURL(fileURLWithPath: "/one/same.pdf"), NSURL(fileURLWithPath: "/two/same.pdf")])
        guard case .files(let selection) = ClipboardReader.read(board) else { XCTFail(); return }
        XCTAssertEqual(selection.urls.count, 2)
    }
}
