import XCTest
import AppKit
import WebKit
@testable import ChatDeskMac
import ChatDeskCore

/// Real WKWebView + WKUIDelegate + File API integration, but NOT real Finder Cmd+V or ChatGPT.
/// Must run on a Mac with a graphical session. Never touches the user's general pasteboard.
@MainActor
final class WebKitFileBridgeTests: XCTestCase {
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
}
