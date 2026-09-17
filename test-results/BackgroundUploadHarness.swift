import Foundation
import AppKit
import WebKit
@testable import ChatDeskMac
import ChatDeskCore

/// Native, local-fixture-only confirmation/foreground harness.
/// It never touches the general pasteboard and never opens ChatGPT.
@main
@MainActor
struct BackgroundUploadHarness {
    static func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value) }
            }
        }
    }

    static func report(in webView: WKWebView) async throws -> [String: Any] {
        let value = try await evaluate("JSON.stringify(window.fixtureReport || {})", in: webView)
        guard let text = value as? String, let data = text.data(using: .utf8),
              let report = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "BackgroundUploadHarness", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Fixture report unavailable"])
        }
        return report
    }

    static func button(named title: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.title == title { return button }
        for child in view.subviews where child.isHidden == false {
            if let match = button(named: title, in: child) { return match }
        }
        return nil
    }

    static func waitForSheet(on window: NSWindow) async throws -> NSWindow {
        for _ in 0..<100 {
            if let sheet = window.attachedSheet { return sheet }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "BackgroundUploadHarness", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Confirmation sheet did not appear"])
    }

    static func files(in directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try (1...25).map { number in
            let url = directory.appendingPathComponent(String(format: "synthetic-%02d.txt", number))
            try Data("synthetic fixture \(number)".utf8).write(to: url)
            return url
        }
    }

    static func run(selection: [URL], accepted: Bool, cancelAfterFirstSend: Bool = false,
                    defaults: UserDefaults, temporary: URL) async throws {
        let controller = MainWindowController(preferences: Preferences(defaults: defaults), fixture: true,
            safeMode: false, libraryDirectory: temporary, websiteDataStore: .nonPersistent())
        defer { _ = controller.prepareToQuit(); controller.window?.orderOut(nil) }
        controller.showAndFocus()
        for _ in 0..<100 {
            if !controller.webView.isLoading, controller.webView.url?.isFileURL == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard controller.webView.url?.isFileURL == true else {
            throw NSError(domain: "BackgroundUploadHarness", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Local fixture did not load"])
        }
        let initialInactivePolicy: String?
        if #available(macOS 14.0, *) {
            initialInactivePolicy = String(describing: controller.webView.configuration.preferences.inactiveSchedulingPolicy)
        } else {
            initialInactivePolicy = nil
        }
        _ = try await evaluate("document.getElementById('prompt-textarea').value='KEEP THIS DRAFT'", in: controller.webView)
        guard controller.requestSuperUpload(FileSelection(urls: selection)) else {
            throw NSError(domain: "BackgroundUploadHarness", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Request was not recognised as a batch"])
        }
        let sheet = try await waitForSheet(on: controller.window!)
        guard let choice = button(named: accepted ? "Yes" : "No", in: sheet.contentView!) else {
            throw NSError(domain: "BackgroundUploadHarness", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Expected confirmation button missing"])
        }
        choice.performClick(nil)

        if !accepted {
            try await Task.sleep(nanoseconds: 500_000_000)
            let result = try await report(in: controller.webView)
            guard (result["files"] as? [[String: Any]])?.isEmpty == true,
                  result["submitted"] as? Int == 0,
                  result["assistantReplies"] as? Int == 0 else {
                throw NSError(domain: "BackgroundUploadHarness", code: 6,
                              userInfo: [NSLocalizedDescriptionKey: "No sent files/messages after declining"])
            }
            let draft = try await evaluate("document.getElementById('prompt-textarea').value", in: controller.webView) as? String
            guard draft == "KEEP THIS DRAFT" else { throw NSError(domain: "BackgroundUploadHarness", code: 7) }
            if #available(macOS 14.0, *) {
                guard String(describing: controller.webView.configuration.preferences.inactiveSchedulingPolicy) == initialInactivePolicy else {
                    throw NSError(domain: "BackgroundUploadHarness", code: 11,
                                  userInfo: [NSLocalizedDescriptionKey: "WK inactive scheduling policy changed after No"])
                }
            }
            print("PASS No: 0 files, 0 messages, draft preserved")
            return
        }

        // This is the foreground-independence check: hide the only app window while
        // the authorised queue is running. No other app or clipboard is involved.
        controller.window?.orderOut(nil)
        var result: [String: Any] = [:]
        if cancelAfterFirstSend {
            for _ in 0..<150 {
                result = try await report(in: controller.webView)
                if result["submitted"] as? Int == 1 { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard result["submitted"] as? Int == 1,
                  (result["files"] as? [[String: Any]])?.count == 10 else {
                throw NSError(domain: "BackgroundUploadHarness", code: 13,
                              userInfo: [NSLocalizedDescriptionKey: "First batch was not observed before cancellation"])
            }
            controller.superUpload.cancel(reason: "Harness cancellation")
            try await Task.sleep(nanoseconds: 3_000_000_000)
            result = try await report(in: controller.webView)
            guard !controller.superUpload.isActive,
                  result["submitted"] as? Int == 1,
                  (result["files"] as? [[String: Any]])?.count == 10 else {
                throw NSError(domain: "BackgroundUploadHarness", code: 14,
                              userInfo: [NSLocalizedDescriptionKey: "Cancellation allowed a later batch to send"])
            }
            if #available(macOS 14.0, *) {
                guard String(describing: controller.webView.configuration.preferences.inactiveSchedulingPolicy) == initialInactivePolicy else {
                    throw NSError(domain: "BackgroundUploadHarness", code: 15,
                                  userInfo: [NSLocalizedDescriptionKey: "WK inactive scheduling policy was not restored after cancel"])
                }
            }
            print("PASS Cancel: hidden-window queue stopped after first batch; no later sends; WK policy restored")
            return
        }
        for _ in 0..<700 {
            result = try await report(in: controller.webView)
            if (result["files"] as? [[String: Any]])?.count == 25,
               result["submitted"] as? Int == 3,
               result["assistantReplies"] as? Int == 3,
               !controller.superUpload.isActive { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard (result["files"] as? [[String: Any]])?.count == 25,
              result["submitted"] as? Int == 3,
              result["assistantReplies"] as? Int == 3,
              !controller.superUpload.isActive else {
            throw NSError(domain: "BackgroundUploadHarness", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "Hidden-window queue did not complete 10/10/5"])
        }
        let messages = result["sentMessages"] as? [String] ?? []
        guard messages.count == 3, messages[0].contains("KEEP THIS DRAFT") else {
            throw NSError(domain: "BackgroundUploadHarness", code: 9,
                          userInfo: [NSLocalizedDescriptionKey: "Initial draft was not preserved in first send"])
        }
        if #available(macOS 14.0, *) {
            guard String(describing: controller.webView.configuration.preferences.inactiveSchedulingPolicy) == initialInactivePolicy else {
                throw NSError(domain: "BackgroundUploadHarness", code: 12,
                              userInfo: [NSLocalizedDescriptionKey: "WK inactive scheduling policy was not restored"])
            }
        }
        print("PASS Yes: hidden window completed 25 files, 3 messages, 3 replies; first draft preserved")
    }

    static func main() async throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let suite = "ChatDesk.background-upload.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw NSError(domain: "BackgroundUploadHarness", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create isolated defaults suite"])
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: temporary) }
        let selection = try files(in: temporary.appendingPathComponent("SyntheticFiles", isDirectory: true))
        let mode = CommandLine.arguments.dropFirst().first ?? "both"
        let alert = MainWindowController.batchUploadConfirmation(fileCount: selection.count)
        guard alert.buttons.count == 2,
              alert.buttons[0].title == "Yes", alert.buttons[1].title == "No",
              alert.buttons[0].keyEquivalent == "\r",
              alert.buttons[1].keyEquivalent == "\u{1b}" else {
            throw NSError(domain: "BackgroundUploadHarness", code: 16,
                          userInfo: [NSLocalizedDescriptionKey: "Confirmation keyboard defaults are incorrect"])
        }
        if mode == "no" || mode == "both" { try await run(selection: selection, accepted: false, defaults: defaults, temporary: temporary) }
        if mode == "yes" || mode == "both" { try await run(selection: selection, accepted: true, defaults: defaults, temporary: temporary) }
        if mode == "cancel" || mode == "both" {
            try await run(selection: selection, accepted: true, cancelAfterFirstSend: true,
                          defaults: defaults, temporary: temporary)
        }
    }
}
