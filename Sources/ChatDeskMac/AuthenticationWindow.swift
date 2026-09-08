import AppKit
import WebKit
import ChatDeskCore

/// Only created when the service requests a normal authentication popup.
/// Uses WebKit's supplied configuration; no cookies or tokens are copied or inspected.
@MainActor
final class AuthenticationWindow: NSWindowController, WKUIDelegate, WKNavigationDelegate, NSWindowDelegate {
    let webView: WKWebView
    let policy: NavigationPolicy
    var onClose: (() -> Void)?
    var onNotice: ((String) -> Void)?
    init(configuration: WKWebViewConfiguration, policy: NavigationPolicy) {
        self.policy = policy
        webView = WKWebView(frame: .zero, configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 740),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ChatPretzel • inloggning"; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = webView; window.delegate = self
        webView.uiDelegate = self; webView.navigationDelegate = self
        window.center(); window.makeKeyAndOrderFront(nil)
    }
    required init?(coder: NSCoder) { nil }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let decision = policy.decision(for: navigationAction.request.url,
            userInitiated: navigationAction.navigationType == .linkActivated, authenticationWindow: true)
        switch decision {
        case .embedded: decisionHandler(.allow)
        case .external:
            decisionHandler(.cancel)
            if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        case .deny:
            decisionHandler(.cancel); onNotice?("Inloggningen ville öppna en ej tillåten adress. Ingen säkerhetskontroll har stängts av.")
        }
    }
    func webViewDidClose(_ webView: WKWebView) { close() }
    func windowWillClose(_ notification: Notification) {
        webView.stopLoading(); webView.uiDelegate = nil; webView.navigationDelegate = nil; onClose?()
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        completionHandler(nil) // This window is for login, never for local-file transfer.
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let window, window.attachedSheet == nil else { completionHandler(); return }
        let alert = NSAlert(); alert.messageText = "Inloggningssidan"; alert.informativeText = String(message.prefix(2000))
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let window, window.attachedSheet == nil else { completionHandler(false); return }
        let alert = NSAlert(); alert.messageText = "Inloggningssidan"; alert.informativeText = String(message.prefix(2000))
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Avbryt")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }
}
