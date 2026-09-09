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

    func testMailRTFDAttachmentIsMaterializedWithoutUsingItsTextPreview() async throws {
        let board = makePasteboard(); defer { board.releaseGlobally() }
        let expected = Data("Mail attachment bytes".utf8)
        let wrapper = FileWrapper(regularFileWithContents: expected)
        wrapper.preferredFilename = "Mail attachment.txt"
        let document = NSMutableAttributedString(string: "Text preview that must not become a filename or prompt")
        document.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
        let rtfd = try document.data(from: NSRange(location: 0, length: document.length),
                                     documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        let item = NSPasteboardItem()
        item.setData(rtfd, forType: NSPasteboard.PasteboardType("com.apple.flat-rtfd"))
        item.setString("Mail attachment.txt", forType: .string)
        XCTAssertTrue(board.writeObjects([item]))

        guard case .mailRichText(let copied, _) = ClipboardReader.read(board) else {
            XCTFail("Expected Mail RTFD data"); return
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatPretzel-mail-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let materializer = MailAttachmentMaterializer(rootDirectory: root)
        let finished = expectation(description: "Mail attachment materialized")
        materializer.receive(copied) { result in
            switch result {
            case .failure(let error): XCTFail("Mail attachment failed: \(error)")
            case .success(nil): XCTFail("Expected one attachment")
            case .success(let selection?):
                XCTAssertEqual(selection.urls.count, 1)
                XCTAssertEqual(selection.urls.first?.lastPathComponent, "Mail attachment.txt")
                XCTAssertEqual(selection.urls.first.flatMap { try? Data(contentsOf: $0) }, expected)
                materializer.release(selection.id)
            }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 5)
    }
}
