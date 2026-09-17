import XCTest
import AppKit
import WebKit
@testable import ChatDeskMac
import ChatDeskCore

/// Real WKWebView + WKUIDelegate + File API integration, but NOT real Finder Cmd+V or ChatGPT.
/// Must run on a Mac with a graphical session. Never touches the user's general pasteboard.
@MainActor
final class WebKitFileBridgeTests: XCTestCase {
    func testSuperUploadOverlayUsesEnglishProgressAndCancel() {
        _ = NSApplication.shared
        let overlay = SuperUploadOverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        var cancelled = false
        overlay.onCancel = { cancelled = true }
        overlay.update(processed: 10, total: 39)

        XCTAssertEqual(overlay.statusText,
                       "Uploading in progress\n10 out of 39 files processed")
        XCTAssertEqual(overlay.cancelButton.title, "Cancel")
        overlay.cancelButton.performClick(nil)
        XCTAssertTrue(cancelled)
    }

    func testSuperUploadRouteTrackerBindsOneGeneratedConversation() throws {
        let home = try XCTUnwrap(URL(string: "https://chatgpt.com/"))
        let first = try XCTUnwrap(URL(string: "https://chatgpt.com/c/first"))
        let firstQuery = try XCTUnwrap(URL(string: "https://chatgpt.com/c/first?model=test#bottom"))
        let second = try XCTUnwrap(URL(string: "https://chatgpt.com/c/second"))
        let library = try XCTUnwrap(URL(string: "https://chatgpt.com/library"))

        var beforeSend = try XCTUnwrap(SuperUploadRouteTracker(startingURL: home))
        XCTAssertFalse(beforeSend.allowsChange(from: home, to: first, maySettleConversation: false))

        var active = try XCTUnwrap(SuperUploadRouteTracker(startingURL: home))
        XCTAssertTrue(active.allowsChange(from: home, to: first, maySettleConversation: true))
        XCTAssertTrue(active.allowsChange(from: first, to: second, maySettleConversation: true))
        XCTAssertTrue(active.lockConversation(at: second))
        XCTAssertFalse(active.allowsChange(from: second, to: firstQuery, maySettleConversation: false))
        XCTAssertFalse(active.allowsChange(from: second, to: library, maySettleConversation: false))

        var existing = try XCTUnwrap(SuperUploadRouteTracker(startingURL: first))
        XCTAssertTrue(existing.allowsChange(from: first, to: firstQuery, maySettleConversation: false))
        XCTAssertFalse(existing.allowsChange(from: first, to: second, maySettleConversation: true))
    }

    func testOriginalFilesThroughRealWebKitPicker() async throws {
        _ = NSApplication.shared
        let suite = "ChatDesk.native-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: temporary) }
        let preferences = Preferences(defaults: defaults)
        let controller = MainWindowController(preferences: preferences, fixture: true, safeMode: false,
            libraryDirectory: temporary, websiteDataStore: .nonPersistent())
        controller.showAndFocus()
        defer { _ = controller.prepareToQuit(); controller.window?.orderOut(nil) }
        for _ in 0..<80 {
            if !controller.webView.isLoading, controller.webView.url?.isFileURL == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("Fixtures/files", isDirectory: true)
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(urls.count, 6)
        controller.attachments.start(FileSelection(urls: urls), requireFocus: false)
        var report: [String: Any] = [:]
        for _ in 0..<100 {
            let value = try await controller.webView.evaluateJavaScript("JSON.stringify(window.fixtureReport || {})")
            if let string = value as? String, let data = string.data(using: .utf8),
               let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                report = object
                if (object["files"] as? [[String: Any]])?.count == 6, object["pending"] as? Int == 0 { break }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let files = try XCTUnwrap(report["files"] as? [[String: Any]])
        XCTAssertEqual(files.count, 6, "No native picker callback means the bridge is BLOCKED; do not replace this with a mock PASS.")
        XCTAssertTrue(files.allSatisfy { $0["matchesExpected"] as? Bool == true })
        XCTAssertEqual(report["submitted"] as? Int, 0)
        XCTAssertTrue(controller.attachments.records.allSatisfy { $0.state == .handedToWebKit })
        // deliberately do NOT mark any item server-confirmed.
    }

    func testTwentyFiveFileSuperUploadNeedsOneNativeEnterThenSendsTenTenFive() async throws {
        _ = NSApplication.shared
        let suite = "ChatDesk.super-upload-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temporary)
        }
        let preferences = Preferences(defaults: defaults)
        let controller = MainWindowController(preferences: preferences, fixture: true, safeMode: false,
            libraryDirectory: temporary, websiteDataStore: .nonPersistent())
        controller.showAndFocus()
        defer { _ = controller.prepareToQuit(); controller.window?.orderOut(nil) }
        for _ in 0..<80 {
            if !controller.webView.isLoading, controller.webView.url?.isFileURL == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let filesDirectory = temporary.appendingPathComponent("ManyFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        let urls = try (1...25).map { number -> URL in
            let url = filesDirectory.appendingPathComponent(String(format: "file-%02d.txt", number))
            try Data("fixture \(number)".utf8).write(to: url)
            return url
        }
        _ = try await controller.webView.evaluateJavaScript(
            """
            window.fixtureSubmitDelayMs=800;
            window.fixtureReplyDelayMs=1200;
            window.fixtureStreamDelayMs=1200;
            window.fixtureVirtualizeMessages=true;
            const oldUser=document.createElement('div');
            oldUser.dataset.messageAuthorRole='user';oldUser.innerText='Older user turn';document.body.append(oldUser);
            const oldAssistant=document.createElement('div');
            oldAssistant.dataset.messageAuthorRole='assistant';oldAssistant.innerText='Older assistant turn';document.body.append(oldAssistant);
            document.getElementById('prompt-textarea').focus();
            """)
        XCTAssertTrue(controller.superUpload.start(FileSelection(urls: urls)))

        var report: [String: Any] = [:]
        var draft = ""
        for _ in 0..<200 {
            let reportValue = try await controller.webView.evaluateJavaScript(
                "JSON.stringify(window.fixtureReport || {})")
            if let string = reportValue as? String, let data = string.data(using: .utf8),
               let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                report = object
            }
            draft = try await controller.webView.evaluateJavaScript(
                "document.getElementById('prompt-textarea').value") as? String ?? ""
            if (report["files"] as? [[String: Any]])?.count == 10,
               report["pending"] as? Int == 0,
               draft.contains("1–10"), draft.contains("25") { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual((report["files"] as? [[String: Any]])?.count, 10)
        XCTAssertEqual(report["submitted"] as? Int, 0,
                       "The initial batch must wait for the user's one real Enter action.")
        XCTAssertTrue(draft.contains("files 1–10 of 25") || draft.contains("filer 1–10 av 25"))
        XCTAssertTrue(draft.contains("15 more files") || draft.contains("Ytterligare 15 filer"))
        XCTAssertEqual(controller.attachments.records.filter {
            $0.state == .handedToWebKit
        }.count, 10)

        _ = try await controller.webView.evaluateJavaScript(
            "document.getElementById('prompt-textarea').value += '\\nPlease compare these files.'")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertTrue(controller.superUpload.isActive, "Editing before first Enter must not cancel the queue.")
        let enter = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36))
        controller.webView.keyDown(with: enter)

        var lockObserved = false
        for _ in 0..<100 {
            let reportValue = try await controller.webView.evaluateJavaScript(
                "JSON.stringify(window.fixtureReport || {})")
            if let string = reportValue as? String, let data = string.data(using: .utf8),
               let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                report = object
                if object["submitted"] as? Int == 1,
                   object["assistantReplies"] as? Int == 0,
                   controller.isSuperUploadInteractionLocked {
                    lockObserved = true
                    break
                }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(lockObserved)
        XCTAssertEqual(controller.superUploadProgressText,
                       "Uploading in progress\n10 out of 25 files processed")
        let lockedURL = controller.webView.url
        controller.newChat()
        XCTAssertEqual(controller.webView.url, lockedURL,
                       "New Chat must be blocked while the Super Upload overlay is active.")
        XCTAssertTrue(controller.superUpload.isActive)

        for _ in 0..<500 {
            let reportValue = try await controller.webView.evaluateJavaScript(
                "JSON.stringify(window.fixtureReport || {})")
            if let string = reportValue as? String, let data = string.data(using: .utf8),
               let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                report = object
                if (object["files"] as? [[String: Any]])?.count == 25,
                   object["submitted"] as? Int == 3,
                   !controller.superUpload.isActive { break }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual((report["files"] as? [[String: Any]])?.count, 25)
        XCTAssertEqual(report["submitted"] as? Int, 3)
        XCTAssertFalse(controller.superUpload.isActive)
        XCTAssertFalse(controller.isSuperUploadInteractionLocked)
        XCTAssertEqual(controller.attachments.records.filter {
            $0.state == .handedToWebKit
        }.count, 25)
    }
}
