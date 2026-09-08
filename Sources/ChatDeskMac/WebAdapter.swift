import Foundation
import WebKit
import ChatDeskCore

@MainActor
final class WebAdapter {
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
    func call(_ method: String, arguments: [String: Any] = [:], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let webView, policy.allowsAdapter(webView.url) else {
            completion(.failure(AdapterError.disallowedPage)); return
        }
        let allowed = ["context", "prepareFiles", "triggerFiles", "validateFiles", "cancelFiles",
                       "getDraft", "insertText", "applyReading", "teardown"]
        guard allowed.contains(method) else { completion(.failure(AdapterError.disallowedPage)); return }
        webView.callAsyncJavaScript(
            "if (!globalThis.ChatDeskAdapter) return {ok:false,error:'Adapter saknas på sidan'}; return globalThis.ChatDeskAdapter[method](args);",
            arguments: ["method": method, "args": arguments], in: nil, in: Self.world) { result in
                switch result {
                case .success(let value):
                    guard let dictionary = value as? [String: Any] else { completion(.failure(AdapterError.invalidResult)); return }
                    completion(.success(dictionary))
                case .failure(let error): completion(.failure(error))
                }
            }
    }
    enum AdapterError: Error { case disallowedPage, invalidResult }
}
