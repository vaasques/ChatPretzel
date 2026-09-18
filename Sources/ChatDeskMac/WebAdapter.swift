import Foundation
import WebKit
import ChatDeskCore

@MainActor
final class WebAdapter {
    /// A WebKit completion can be withheld while a page is under severe load.
    /// Keep a one-shot gate on the main actor so a timed-out Super Upload state
    /// query unlocks safely instead of leaving the native interaction shield up
    /// forever. Late WebKit callbacks are deliberately ignored.
    private final class CallGate {
        private var completed = false
        private var watchdog: DispatchWorkItem?
        private let completion: (Result<[String: Any], Error>) -> Void

        init(completion: @escaping (Result<[String: Any], Error>) -> Void) {
            self.completion = completion
        }

        func startWatchdog(after timeout: TimeInterval, method: String) {
            guard timeout > 0 else { return }
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.finish(.failure(AdapterError.timedOut(method)))
                }
            }
            watchdog = work
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
        }

        func finish(_ result: Result<[String: Any], Error>) {
            guard !completed else { return }
            completed = true
            watchdog?.cancel()
            watchdog = nil
            completion(result)
        }
    }

    static let world = WKContentWorld.world(name: "ChatDesk.NativeAdapter.v1")
    weak var webView: WKWebView?
    let policy: NavigationPolicy
    init(webView: WKWebView, policy: NavigationPolicy) { self.webView = webView; self.policy = policy }

    static func install(on controller: WKUserContentController, messageHandler: WKScriptMessageHandler) throws {
        let code = try AppResources.text("Adapter.js")
        controller.addUserScript(WKUserScript(source: code, injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true, in: world))
        controller.add(messageHandler, contentWorld: world, name: "chatdesk")
    }
    func call(_ method: String, arguments: [String: Any] = [:], timeout: TimeInterval? = 15,
              completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let webView, policy.allowsAdapter(webView.url) else {
            completion(.failure(AdapterError.disallowedPage)); return
        }
        let allowed = ["context", "prepareFiles", "triggerFiles", "validateFiles", "cancelFiles",
                       "beginSuperUpload", "configureSuperUploadBatch", "removeFailedSuperUploadFiles",
                       "appendSuperUploadMessage", "superUploadState",
                       "submitSuperUpload", "endSuperUpload", "getDraft", "insertText",
                       "applyReading", "teardown"]
        guard allowed.contains(method) else { completion(.failure(AdapterError.disallowedPage)); return }
        let gate = CallGate(completion: completion)
        if let timeout { gate.startWatchdog(after: timeout, method: method) }
        webView.callAsyncJavaScript(
            "if (!globalThis.ChatDeskAdapter) return {ok:false,error:'The adapter is missing from the page'}; return globalThis.ChatDeskAdapter[method](args);",
            arguments: ["method": method, "args": arguments], in: nil, in: Self.world) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let value):
                        guard let dictionary = value as? [String: Any] else {
                            gate.finish(.failure(AdapterError.invalidResult)); return
                        }
                        gate.finish(.success(dictionary))
                    case .failure(let error): gate.finish(.failure(error))
                    }
                }
            }
    }
    enum AdapterError: LocalizedError {
        case disallowedPage
        case invalidResult
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case .disallowedPage: return "The current page does not allow this ChatPretzel action."
            case .invalidResult: return "ChatGPT returned an invalid page response."
            case .timedOut:
                return "ChatGPT's page did not confirm whether the Super Upload action completed in time. Super Upload stopped to avoid sending a duplicate; check the conversation before retrying."
            }
        }
    }
}
