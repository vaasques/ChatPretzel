import XCTest
@testable import ChatDeskCore

final class NavigationTests: XCTestCase {
    let policy = NavigationPolicy()
    func testRealChatHosts() {
        for host in ["chatgpt.com", "chat.openai.com"] { XCTAssertTrue(policy.isChat(URL(string: "https://\(host)/c/123"))) }
    }
    func testLookalikeHostsRejected() {
        for host in ["chatgpt.com.evil.test", "evilchatgpt.com", "foo.chatgpt.com", "openai.com.evil.test"] {
            XCTAssertFalse(policy.isChat(URL(string: "https://\(host)/")))
        }
    }
    func testWrongProtocolAndPortRejected() {
        XCTAssertFalse(policy.isChat(URL(string: "http://chatgpt.com/")))
        XCTAssertFalse(policy.isChat(URL(string: "https://chatgpt.com:8443/")))
        XCTAssertTrue(policy.isChat(URL(string: "https://chatgpt.com:443/")))
    }
    func testUserInfoRejected() { XCTAssertFalse(policy.isChat(URL(string: "https://name:secret@chatgpt.com/"))) }
    func testExternalNeedsUserAction() {
        let url = URL(string: "https://example.com/")!
        XCTAssertEqual(policy.decision(for: url, userInitiated: true), .external)
        XCTAssertEqual(policy.decision(for: url, userInitiated: false), .deny)
    }
    func testUnsafeSchemesRejectedEvenOnClick() {
        for text in ["file:///etc/passwd", "javascript:alert(1)", "data:text/html,hello", "ftp://example.com/file"] {
            XCTAssertEqual(policy.decision(for: URL(string: text), userInitiated: true), .deny)
        }
    }
    func testAuthenticationExactHost() {
        XCTAssertTrue(policy.isAuthentication(URL(string: "https://accounts.google.com/signin")))
        XCTAssertFalse(policy.isAuthentication(URL(string: "https://accounts.google.com.evil.test/")))
    }
    func testFixtureOnlyExactFile() {
        let file = URL(fileURLWithPath: "/test/ClipboardFixture.html")
        let local = NavigationPolicy(fixtureURL: file)
        XCTAssertTrue(local.isFixture(file))
        XCTAssertFalse(local.isFixture(URL(fileURLWithPath: "/other/ClipboardFixture.html")))
        XCTAssertFalse(local.isFixture(URL(fileURLWithPath: "/test/secret.txt")))
        XCTAssertFalse(policy.isFixture(file))
    }
    func testRemoteHostCannotMasqueradeAsFixture() {
        let policy = NavigationPolicy(fixtureURL: URL(fileURLWithPath: "/test/ClipboardFixture.html"))
        XCTAssertFalse(policy.isFixture(URL(string: "file://remote.example/test/ClipboardFixture.html")))
        XCTAssertFalse(policy.isFixture(URL(string: "file://name:secret@localhost/test/ClipboardFixture.html")))
    }
    func testBlobNotNativeIntegration() {
        let url = URL(string: "blob:https://chatgpt.com/123")!
        XCTAssertTrue(policy.isChatBlob(url)); XCTAssertFalse(policy.allowsAdapter(url))
        XCTAssertFalse(policy.isChatBlob(URL(string: "blob:https://evil.test/123")))
    }
    func testBlankOnlyAuthenticationWindow() {
        XCTAssertEqual(policy.decision(for: URL(string: "about:blank"), userInitiated: false), .deny)
        XCTAssertEqual(policy.decision(for: URL(string: "about:blank"), userInitiated: false, authenticationWindow: true), .embedded)
    }
}

final class PermitTests: XCTestCase {
    let page = PageIdentity(href: "https://chatgpt.com/c/one", documentID: "one", generation: 1)
    let now = Date(timeIntervalSince1970: 1000)
    func testPermitOneShot() throws {
        var permit = UploadPermit(page: page, now: now)
        try permit.consume(page: page, mainFrame: true, now: now)
        XCTAssertThrowsError(try permit.consume(page: page, mainFrame: true, now: now)) { XCTAssertEqual($0 as? UploadPermit.Failure, .alreadyConsumed) }
    }
    func testExpiredPermit() {
        var permit = UploadPermit(page: page, now: now)
        XCTAssertThrowsError(try permit.consume(page: page, mainFrame: true, now: now.addingTimeInterval(6))) {
            XCTAssertEqual($0 as? UploadPermit.Failure, .expired)
        }
    }
    func testChangedConversation() {
        var permit = UploadPermit(page: page, now: now)
        let other = PageIdentity(href: "https://chatgpt.com/c/two", documentID: "one", generation: 1)
        XCTAssertThrowsError(try permit.consume(page: other, mainFrame: true, now: now))
    }
    func testChangedDocumentSameAddress() {
        var permit = UploadPermit(page: page, now: now)
        let other = PageIdentity(href: page.href, documentID: "two", generation: 1)
        XCTAssertThrowsError(try permit.consume(page: other, mainFrame: true, now: now))
    }
    func testChangedGenerationSameDocument() {
        var permit = UploadPermit(page: page, now: now)
        let other = PageIdentity(href: page.href, documentID: "one", generation: 2)
        XCTAssertThrowsError(try permit.consume(page: other, mainFrame: true, now: now))
    }
    func testSubframeDenied() {
        var permit = UploadPermit(page: page, now: now)
        XCTAssertThrowsError(try permit.consume(page: page, mainFrame: false, now: now)) {
            XCTAssertEqual($0 as? UploadPermit.Failure, .rejectedFrame)
        }
    }
}

final class FileSelectionTests: XCTestCase {
    func testKeepsAllMixedTypesInOrder() {
        let urls = ["pdf", "docx", "xlsx", "png", "jpg", "txt"].map { URL(fileURLWithPath: "/test/\($0).\($0)") }
        XCTAssertEqual(FileSelection(urls: urls).urls, urls)
    }
    func testSameNameDifferentDirectoriesSurvives() {
        let urls = [URL(fileURLWithPath: "/one/test.pdf"), URL(fileURLWithPath: "/two/test.pdf")]
        XCTAssertEqual(FileSelection(urls: urls).urls.count, 2)
    }
    func testDuplicatesWithinOperationOnly() {
        let url = URL(fileURLWithPath: "/one/test.pdf")
        let first = FileSelection(urls: [url, url]); let second = FileSelection(urls: [url])
        XCTAssertEqual(first.urls.count, 1); XCTAssertNotEqual(first.id, second.id)
    }
    func testUnicodeFilename() {
        let url = URL(fileURLWithPath: "/one/å ä ö 日本.txt")
        XCTAssertEqual(FilePolicy.url(fromTypedRepresentation: url.absoluteString), url)
    }
    func testPlainPathAndNetworkURLsDoNotGrantFileAccess() {
        XCTAssertNil(FilePolicy.url(fromTypedRepresentation: "/Users/user/private.txt"))
        XCTAssertNil(FilePolicy.url(fromTypedRepresentation: "https://example.com/file.pdf"))
        XCTAssertNil(FilePolicy.url(fromTypedRepresentation: "file://remotehost/etc/passwd"))
    }
    func testDownloadFilenameSanitization() {
        XCTAssertEqual(FilePolicy.safeDownloadName("../../secret.pdf"), "secret.pdf")
        XCTAssertEqual(FilePolicy.safeDownloadName("C:\\one\\two.docx"), "two.docx")
        XCTAssertEqual(FilePolicy.safeDownloadName("\u{0}test\n.pdf"), "test.pdf")
        XCTAssertEqual(FilePolicy.safeDownloadName(".."), "Download")
    }
    func testStateDoesNotInventUploadSuccess() {
        var item = AttachmentRecord(operationID: UUID(), filename: "one.pdf")
        XCTAssertFalse(item.transition(to: .userConfirmed))
        XCTAssertTrue(item.transition(to: .checking)); XCTAssertTrue(item.transition(to: .waitingForWebKit))
        XCTAssertTrue(item.transition(to: .handedToWebKit))
        XCTAssertFalse(item.transition(to: .cancelled)) // Cannot claim to recall already handed files.
        XCTAssertTrue(item.transition(to: .unknown)); XCTAssertTrue(item.transition(to: .userConfirmed))
    }
    func testFailedItemCannotSilentlyRetry() {
        var item = AttachmentRecord(operationID: UUID(), filename: "one.pdf")
        item.transition(to: .checking); item.transition(to: .failed)
        XCTAssertFalse(item.transition(to: .handedToWebKit))
    }
}

final class LocalStoreTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    var store: LibraryStore { LibraryStore(url: directory.appendingPathComponent("library.json")) }
    func testMissingStoreIsEmpty() throws { XCTAssertEqual(try store.load(), LibraryDocument()) }
    func testAtomicRoundTripAndBackup() throws {
        let first = LibraryDocument(entries: [LibraryEntry(kind: .note, title: "åäö", text: "Text")])
        try store.save(first); XCTAssertEqual(try store.load(), first)
        let second = LibraryDocument(entries: [LibraryEntry(kind: .prompt, title: "Other", text: "{{task}}")])
        try store.save(second)
        XCTAssertEqual(try store.load(), second)
        let previous = try LibraryStore.decode(Data(contentsOf: store.url.appendingPathExtension("backup")))
        XCTAssertEqual(previous, first)
    }
    func testCorruptOriginalIsPreserved() throws {
        let data = Data("not json".utf8); try data.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(LibraryDocument()))
        XCTAssertEqual(try Data(contentsOf: store.url), data)
    }
    func testUnknownSchemaIsNotOverwritten() throws {
        let original = Data(#"{"schemaVersion":999,"entries":[]}"#.utf8); try original.write(to: store.url)
        XCTAssertThrowsError(try store.save(LibraryDocument()))
        XCTAssertEqual(try Data(contentsOf: store.url), original)
    }
    func testDuplicateIDsRejected() {
        let item = LibraryEntry(kind: .note, title: "one")
        XCTAssertThrowsError(try LibraryDocument(entries: [item, item]).validate())
    }
    func testUnsafeBookmarkRejected() {
        let item = LibraryEntry(kind: .bookmark, title: "bad", url: "file:///etc/passwd")
        XCTAssertThrowsError(try LibraryDocument(entries: [item]).validate())
    }
    func testOversizedDocumentRejected() {
        let item = LibraryEntry(kind: .note, title: "big", text: String(repeating: "x", count: 65_537))
        XCTAssertThrowsError(try LibraryDocument(entries: [item]).validate())
    }
    func testOversizedInputRejectedBeforeDecode() {
        XCTAssertThrowsError(try LibraryStore.decode(Data(repeating: 0, count: LibraryStore.maximumBytes + 1)))
    }
}

final class DraftAndTemplateTests: XCTestCase {
    func testTemporaryDraftNotStored() {
        var buffer = DraftBuffer(); buffer.put(href: "https://chatgpt.com/", text: "private", isTemporary: true)
        XCTAssertEqual(buffer.count, 0)
    }
    func testDraftsBoundedAndEmptyRemoves() {
        var buffer = DraftBuffer(capacity: 2)
        for i in 0..<3 { buffer.put(href: "https://chatgpt.com/c/\(i)", text: "draft", isTemporary: false, now: Date(timeIntervalSince1970: Double(i))) }
        XCTAssertEqual(buffer.count, 2); XCTAssertNil(buffer.draft(for: "https://chatgpt.com/c/0"))
        buffer.put(href: "https://chatgpt.com/c/2", text: "", isTemporary: false)
        XCTAssertEqual(buffer.count, 1)
    }
    func testNoDraftFromUntrustedPage() {
        var buffer = DraftBuffer(); buffer.put(href: "https://evil.test/", text: "bad", isTemporary: false)
        XCTAssertEqual(buffer.count, 0)
    }
    func testOversizedUnicodeDraftRejected() {
        var buffer = DraftBuffer(); buffer.put(href: "https://chatgpt.com/", text: String(repeating: "å", count: 40_000), isTemporary: false)
        XCTAssertEqual(buffer.count, 0)
    }
    func testPrivacyBoundaryClear() {
        var buffer = DraftBuffer(); buffer.put(href: "https://chatgpt.com/", text: "one", isTemporary: false)
        buffer.removeAll(); XCTAssertEqual(buffer.count, 0)
    }
    func testPromptVariablesUniqueAndUnicode() {
        XCTAssertEqual(PromptTemplate.variables(in: "{{task}} {{namn å}} {{task}}"), ["task", "namn å"])
    }
    func testPromptValuesNotRecursivelyExpanded() {
        XCTAssertEqual(PromptTemplate.render("{{one}} {{two}}", values: ["one":"{{two}}", "two":"done"]), "{{two}} done")
    }
    func testPromptUnfilledVariableKept() { XCTAssertEqual(PromptTemplate.render("Hello {{who}}", values: [:]), "Hello {{who}}") }
    func testMalformedMessageRejected() { XCTAssertNil(AdapterMessage.parse(["kind":"draft", "text":"secret"])) }
    func testNoFilesystemRPC() {
        for type in ["readFile", "readClipboard", "shell", "fetch", "upload"] { XCTAssertNil(AdapterMessage.parse(["kind":type,"path":"/etc/passwd"])) }
    }
    func testValidDraftMessageParsed() {
        XCTAssertEqual(AdapterMessage.parse(["kind":"draft", "href":"https://chatgpt.com/", "documentID":"id", "text":"hello", "temporary":false]),
                       .draft(href: "https://chatgpt.com/", documentID: "id", text: "hello", temporary: false))
    }
}
