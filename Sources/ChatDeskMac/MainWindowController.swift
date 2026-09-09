import AppKit
import WebKit
import ChatDeskCore

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, WKUIDelegate,
                                  WKNavigationDelegate, WKScriptMessageHandler, NSSearchFieldDelegate {
    let preferences: Preferences
    let library: LibraryController
    private let websiteDataStoreOverride: WKWebsiteDataStore?
    let downloads = DownloadCoordinator()
    private(set) var webView: NativeWebView!
    private(set) var adapter: WebAdapter!
    private(set) var attachments: AttachmentCoordinator!
    private var observations: [NSKeyValueObservation] = []
    private var authenticationWindows: [UUID: AuthenticationWindow] = [:]
    private var transfersPanel: TransferPanel?
    private var downloadsPanel: DownloadsPanel?
    private var libraryPanel: LibraryPanel?
    private var settingsPanel: SettingsPanel?
    private let mailAttachments = MailAttachmentMaterializer()
    private let webContainer = NSView()
    private let status = NSTextField(labelWithString: "Development build • native Mac build and ChatGPT compatibility require testing")
    private let locationLabel = NSTextField(labelWithString: "chatgpt.com")
    private let progress = NSProgressIndicator()
    private let search = NSSearchField()
    private let searchRow = NSStackView()
    private var navigationGeneration: UInt64 = 0
    private var observedURL: URL?
    private var knownDocumentID: String?
    private var drafts = DraftBuffer()
    private let forcedSafeMode: Bool
    private(set) var fixtureMode: Bool
    let policy: NavigationPolicy
    var onPreferencesChanged: (() -> Void)?
    var effectiveSafeMode: Bool { forcedSafeMode || preferences.safeMode }

    init(preferences: Preferences, fixture: Bool, safeMode: Bool,
         libraryDirectory: URL? = nil, websiteDataStore: WKWebsiteDataStore? = nil) {
        self.library = LibraryController(directory: libraryDirectory)
        self.websiteDataStoreOverride = websiteDataStore
        self.preferences = preferences; fixtureMode = fixture; forcedSafeMode = safeMode
        policy = NavigationPolicy(fixtureURL: AppResources.url("ClipboardFixture.html"))
        let window = ChatWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 790),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "ChatPretzel"; window.minSize = NSSize(width: 720, height: 480); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
        makeLayout()
        window.setFrameAutosaveName("ChatDesk.Main")
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersection(window.frame).width > 120 && $0.visibleFrame.intersection(window.frame).height > 80 }) { window.center() }
        window.interceptFilePaste = { [weak self] in self?.handleFilePaste() ?? false }
        window.mapControlCV = { [weak self] in self?.preferences.controlCV == true }
        downloads.window = window; downloads.onNotice = { [weak self] in self?.notice($0) }
        downloads.onChange = { [weak self] in self?.downloadsPanel?.refresh() }
        library.onError = { [weak self] in self?.notice($0) }; library.load()
        makeWebView()
    }
    required init?(coder: NSCoder) { nil }

    private func makeLayout() {
        guard let window else { return }
        let bar = NSStackView(); bar.spacing = 7; bar.alignment = .centerY
        let items: [(String, String, Selector)] = [
            ("chevron.left", "Back", #selector(back)), ("chevron.right", "Forward", #selector(forward)),
            ("plus", "New Chat", #selector(newChat)), ("arrow.clockwise", "Reload", #selector(reload)),
            ("paperclip", "Choose Multiple Files", #selector(chooseFiles)), ("books.vertical", "Local Library", #selector(showLibrary)),
            ("tray.full", "Attachment Status", #selector(showTransfers)), ("arrow.down.to.line", "Downloads", #selector(showDownloads))]
        for (symbol, title, action) in items {
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(), target: self, action: action)
            button.bezelStyle = .texturedRounded; button.toolTip = title; button.setAccessibilityLabel(title); bar.addArrangedSubview(button)
        }
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); bar.addArrangedSubview(spacer)
        locationLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular); locationLabel.textColor = .secondaryLabelColor
        bar.addArrangedSubview(locationLabel)
        let gear = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") ?? NSImage(), target: self, action: #selector(showSettings))
        gear.bezelStyle = .texturedRounded; gear.toolTip = "Settings"; bar.addArrangedSubview(gear)
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        search.placeholderString = "Find on page"; search.target = self; search.action = #selector(findNext); search.delegate = self
        searchRow.addArrangedSubview(search)
        searchRow.addArrangedSubview(NSButton(title: "Next", target: self, action: #selector(findNext)))
        searchRow.addArrangedSubview(NSButton(title: "Close", target: self, action: #selector(hideSearch)))
        searchRow.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 6, right: 10); searchRow.spacing = 8; searchRow.isHidden = true
        progress.style = .bar; progress.minValue = 0; progress.maxValue = 1; progress.isIndeterminate = false; progress.isHidden = true
        progress.heightAnchor.constraint(equalToConstant: 2).isActive = true
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; status.lineBreakMode = .byTruncatingTail
        let footer = NSStackView(views: [status]); footer.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 7, right: 12)
        let stack = NSStackView(views: [bar, searchRow, progress, webContainer, footer]); stack.orientation = .vertical; stack.spacing = 0; stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView(); window.contentView = root; root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)])
        for view in [bar, searchRow, progress, webContainer, footer] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        webContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        webContainer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }
    private func makeWebView(restoringURL: URL? = nil) {
        observations.removeAll()
        attachments?.cancel(); transfersPanel?.close(); transfersPanel = nil
        if let old = webView { old.stopLoading(); old.uiDelegate = nil; old.navigationDelegate = nil; old.removeFromSuperview() }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStoreOverride ?? .default() // Tests inject non-persistent storage; the app uses its own sandbox.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController = WKUserContentController()
        if !effectiveSafeMode {
            do { try WebAdapter.install(on: configuration.userContentController, messageHandler: WeakScriptHandler(self)) }
            catch { notice("The adapter resource is missing. The basic website will open without enhancements.") }
        }
        webView = NativeWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.uiDelegate = self; webView.navigationDelegate = self; webView.allowsBackForwardNavigationGestures = true
        webView.pageZoom = preferences.zoom
        webContainer.addSubview(webView)
        NSLayoutConstraint.activate([webView.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor), webView.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
            webView.topAnchor.constraint(equalTo: webContainer.topAnchor), webView.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor)])
        adapter = WebAdapter(webView: webView, policy: policy)
        attachments = AttachmentCoordinator(adapter: adapter)
        attachments.generation = { [weak self] in self?.navigationGeneration ?? 0 }
        attachments.onNotice = { [weak self] in self?.notice($0) }
        attachments.onChange = { [weak self] in self?.transfersPanel?.refresh() }
        attachments.onReleaseOperation = { [weak self] in self?.mailAttachments.release($0) }
        webView.mayHandleDrop = { [weak self] in
            guard let self else { return false }; return !self.effectiveSafeMode && self.preferences.assistedPaste && self.policy.allowsAdapter(self.webView.url)
        }
        webView.onFileDrop = { [weak self] selection in
            self?.attachments.start(selection, requireFocus: false); self?.showTransfersIfFailedRepresentations(selection); return true
        }
        webView.onUnsupportedDrop = { [weak self] in self?.notice($0) }
        observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
            DispatchQueue.main.async { self?.progress.doubleValue = view.estimatedProgress }
        })
        observations.append(webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            DispatchQueue.main.async { self?.progress.isHidden = !view.isLoading }
        })
        observations.append(webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.urlChanged() }
        })
        observedURL = nil; knownDocumentID = nil; navigationGeneration &+= 1
        if fixtureMode, let url = policy.fixtureURL { webView.loadFileURL(url, allowingReadAccessTo: url) }
        else {
            fixtureMode = false
            let destination = policy.isChat(restoringURL) ? restoringURL! : URL(string: "https://chatgpt.com/")!
            webView.load(URLRequest(url: destination))
        }
    }
    private func urlChanged() {
        guard observedURL != webView.url else { return }
        observedURL = webView.url; navigationGeneration &+= 1; knownDocumentID = nil
        attachments.navigationChanged()
        locationLabel.stringValue = policy.isFixture(webView.url) ? "Local file test – no upload" : (webView.url?.host ?? "")
        if !policy.isChat(webView.url) { drafts.removeAll() }
        updateAdapterContext()
    }
    private func updateAdapterContext() {
        guard !effectiveSafeMode else { return }
        let expected = navigationGeneration
        adapter.call("context") { [weak self] result in
            guard let self, self.navigationGeneration == expected, case .success(let info) = result,
                  info["href"] as? String == self.webView.url?.absoluteString else { return }
            self.knownDocumentID = info["documentID"] as? String
            self.adapter.call("applyReading", arguments: ["width": self.preferences.readingWidth]) { _ in }
        }
    }
    func notice(_ message: String) { status.stringValue = message; status.toolTip = message }
    func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    func prepareToQuit() -> Bool {
        if libraryPanel?.allowLeave() == false { return false }
        if !library.finishWrites() {
            let alert = NSAlert(); alert.messageText = "The library has not been saved to disk."
            alert.informativeText = "Cancel and export the library to keep your changes."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Quit Anyway")
            guard alert.runModal() == .alertSecondButtonReturn else { return false }
        }
        attachments.cancel(); downloads.cancelAll(); mailAttachments.cleanupAll()
        for auth in authenticationWindows.values { auth.onClose = nil; auth.close() }
        authenticationWindows.removeAll(); webView.stopLoading(); return true
    }
    private var webHasFocus: Bool {
        guard window?.isKeyWindow == true, let focused = window?.firstResponder as? NSView else { return false }
        return focused === webView || focused.isDescendant(of: webView)
    }
    func handleFilePaste() -> Bool {
        guard webHasFocus, !effectiveSafeMode, preferences.assistedPaste, policy.allowsAdapter(webView.url) else { return false }
        switch ClipboardReader.read(.general) {
        case .files(let selection): attachments.start(selection, requireFocus: true); showTransfersIfFailedRepresentations(selection); return true
        case .mailRichText(let data, let changeCount):
            let expectedGeneration = navigationGeneration
            let expectedURL = webView.url
            notice("Preparing attachments copied from Mail…")
            mailAttachments.receive(data) { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let error): self.notice(error.localizedDescription)
                case .success(nil):
                    guard self.navigationGeneration == expectedGeneration, self.webView.url == expectedURL,
                          self.webHasFocus, NSPasteboard.general.changeCount == changeCount else {
                        self.notice("The page, focus, or clipboard changed while the paste was being checked. Nothing was pasted.")
                        return
                    }
                    if !NSApp.sendAction(Selector(("paste:")), to: nil, from: self) {
                        self.notice("The copied content did not contain a Mail attachment and normal paste could not be completed.")
                    }
                case .success(let selection?):
                    guard self.navigationGeneration == expectedGeneration, self.webView.url == expectedURL else {
                        self.mailAttachments.release(selection.id)
                        self.notice("The page changed while Mail was preparing the attachments. No files were sent.")
                        return
                    }
                    if !self.attachments.start(selection, requireFocus: true) {
                        self.mailAttachments.release(selection.id)
                    }
                }
            }
            return true
        case .unsupported(let message): notice(message); return true
        case .useSystemPaste: return false
        }
    }
    private func showTransfersIfFailedRepresentations(_ selection: FileSelection) {
        if selection.rejectedRepresentations > 0 { showTransfers() }
    }
    func pasteFromMenu() {
        if !handleFilePaste() { _ = NSApp.sendAction(Selector(("paste:")), to: nil, from: self) }
    }
    @objc func back() { webView.goBack() }
    @objc func forward() { webView.goForward() }
    @objc func newChat() { fixtureMode = false; webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!)) }
    @objc func reload() {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = "Reload the page?"; alert.informativeText = "Unsent text and web attachments may be lost. Nothing is sent again automatically."
        alert.addButton(withTitle: "Reload"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in if response == .alertFirstButtonReturn { self?.webView.reload() } }
    }
    @objc func chooseFiles() {
        guard policy.allowsAdapter(webView.url), let window, window.attachedSheet == nil,
              let page = webView.url else { notice("Open ChatGPT's message field first."); return }
        if effectiveSafeMode { notice("Use the website's own attachment button in Safe Mode."); return }
        let expected = navigationGeneration
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.title = "Choose Original Files"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            guard self.navigationGeneration == expected, self.webView.url == page else { self.notice("The page changed. No files were sent."); return }
            self.attachments.start(FileSelection(urls: panel.urls), requireFocus: false)
        }
    }
    @objc func showTransfers() {
        if transfersPanel == nil { transfersPanel = TransferPanel(coordinator: attachments); transfersPanel?.window?.center() }
        transfersPanel?.refresh(); transfersPanel?.showWindow(nil); transfersPanel?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func showDownloads() {
        if downloadsPanel == nil { downloadsPanel = DownloadsPanel(coordinator: downloads); downloadsPanel?.window?.center() }
        downloadsPanel?.refresh(); downloadsPanel?.showWindow(nil); downloadsPanel?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func showLibrary() {
        if libraryPanel == nil {
            libraryPanel = LibraryPanel(model: library); libraryPanel?.window?.center()
            libraryPanel?.onInsert = { [weak self] in self?.insertPrompt($0) }
            libraryPanel?.onOpen = { [weak self] url in self?.showAndFocus(); self?.webView.load(URLRequest(url: url)) }
        }
        libraryPanel?.showWindow(nil); libraryPanel?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func showSettings() {
        settingsPanel = SettingsPanel(preferences: preferences)
        settingsPanel?.onApply = { [weak self] in
            guard let self else { return }
            let current = self.webView.url
            self.makeWebView(restoringURL: current); self.onPreferencesChanged?()
        }
        settingsPanel?.window?.center(); settingsPanel?.showWindow(nil)
    }
    @objc func showSearch() { searchRow.isHidden = false; window?.makeFirstResponder(search) }
    @objc private func hideSearch() { searchRow.isHidden = true; window?.makeFirstResponder(webView) }
    @objc private func findNext() {
        guard !search.stringValue.isEmpty else { return }
        let configuration = WKFindConfiguration(); configuration.wraps = true
        webView.find(search.stringValue, configuration: configuration) { [weak self] result in
            if !result.matchFound { self?.notice("No match was found on the loaded page.") }
        }
    }
    func changeZoom(_ delta: Double) { preferences.zoom += delta; webView.pageZoom = preferences.zoom }
    func resetZoom() { preferences.zoom = 1; webView.pageZoom = 1 }
    func openFixture() {
        guard let url = policy.fixtureURL else { notice("The local test file is missing."); return }
        fixtureMode = true; webView.loadFileURL(url, allowingReadAccessTo: url)
    }
    func addBookmark() {
        guard let url = webView.url, policy.isChat(url) else { notice("Only ChatGPT links can be saved here."); return }
        showLibrary(); libraryPanel?.add(LibraryEntry(kind: .bookmark, title: "Return to Chat", url: url.absoluteString))
    }
    func saveCurrentDraft() {
        guard !effectiveSafeMode else { notice("Draft reading is disabled in Safe Mode."); return }
        adapter.call("getDraft") { [weak self] result in
            guard let self, case .success(let info) = result, info["temporary"] as? Bool == false,
                  let text = info["text"] as? String, !text.isEmpty,
                  let href = info["href"] as? String, self.policy.isChat(URL(string: href)) else {
                self?.notice("There is no draft to save. Temporary chats are not saved."); return
            }
            self.showLibrary(); self.libraryPanel?.add(LibraryEntry(kind: .draft, title: "Saved Draft", text: text, url: href))
        }
    }
    func restoreSessionDraft() {
        guard let href = webView.url?.absoluteString, let draft = drafts.draft(for: href), let window else {
            notice("There is no session draft for this address. Drafts from another account or a previous app session are never restored automatically."); return
        }
        let alert = NSAlert(); alert.messageText = "Restore the session draft?"
        alert.informativeText = "Make sure you are in the correct account and chat. Existing text will not be overwritten."
        alert.addButton(withTitle: "Restore into Empty Field"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, self.webView.url?.absoluteString == href else { return }
            self.adapter.call("insertText", arguments: ["text": draft.text, "onlyIfEmpty": true]) { result in
                if case .success(let info) = result, info["ok"] as? Bool == true { return }
                self.notice("The draft was not inserted. Existing text was left unchanged.")
            }
        }
    }
    private func insertPrompt(_ text: String) {
        guard !effectiveSafeMode else { notice("Prompt insertion is disabled in Safe Mode. Copy from the library instead."); return }
        var values: [String: String] = [:]
        for key in PromptTemplate.variables(in: text) {
            let alert = NSAlert(); alert.messageText = "Value for {{\(key)}}"
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 26)); alert.accessoryView = field
            alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }; values[key] = field.stringValue
        }
        showAndFocus()
        adapter.call("insertText", arguments: ["text": PromptTemplate.render(text, values: values)]) { [weak self] result in
            if case .success(let info) = result, info["ok"] as? Bool == true { self?.notice("Text inserted. The message has not been sent.") }
            else { self?.notice("The text could not be inserted. Use Copy in the library and paste it manually.") }
        }
    }

    // MARK: WebKit delegates
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateAdapterContext()
        notice(effectiveSafeMode ? "Safe Mode • basic website without adapter" : (policy.isFixture(webView.url) ? "Local file test • not live ChatGPT verification" : "Page loaded • ChatPretzel 0.2.0"))
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationGeneration &+= 1; knownDocumentID = nil; attachments.navigationChanged()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { notice("The page could not be loaded (error \((error as NSError).code)). Nothing is resent automatically. Try Reload.") }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        notice("Loading stopped (error \((error as NSError).code)). Reload manually if needed.")
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        attachments.navigationChanged(); notice("WebKit's web process ended. A text draft may remain in session memory. Nothing reloads or sends automatically.")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        if let frame = navigationAction.targetFrame, !frame.isMainFrame {
            decisionHandler(url?.scheme == "https" || url?.absoluteString == "about:blank" ? .allow : .cancel); return
        }
        if navigationAction.shouldPerformDownload,
           policy.allowsAdapter(navigationAction.sourceFrame.request.url),
           url?.scheme == "https" || policy.isChatBlob(url) || (policy.isFixture(webView.url) && url?.scheme == "blob") {
            decisionHandler(.download); return
        }
        if policy.isChatBlob(url) { decisionHandler(.allow); return }
        switch policy.decision(for: url, userInitiated: navigationAction.navigationType == .linkActivated) {
        case .embedded: decisionHandler(.allow)
        case .external:
            decisionHandler(.cancel); if let url { NSWorkspace.shared.open(url) }
        case .deny:
            decisionHandler(.cancel); notice("Navigation blocked. Only ChatGPT and explicitly allowed sign-in pages open inside the app.")
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { downloads.accept(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { downloads.accept(download) }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        if attachments.handlePicker(parameters: parameters, frame: frame, completion: completionHandler) { return }
        guard frame.isMainFrame, policy.allowsAdapter(frame.request.url), let page = webView.url,
              let window, window.attachedSheet == nil else { completionHandler(nil); return }
        let expected = navigationGeneration
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, self.webView.url == page, self.navigationGeneration == expected else { completionHandler(nil); return }
            self.attachments.deliverPanelSelection(panel.urls, pageURL: page, pageGeneration: expected, completion: completionHandler)
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        if policy.isAuthentication(url) || (url?.absoluteString == "about:blank" && policy.isAuthentication(webView.url)) {
            guard authenticationWindows.count < 2 else { notice("Too many sign-in windows are open."); return nil }
            let id = UUID(); let controller = AuthenticationWindow(configuration: configuration, policy: policy)
            controller.onNotice = { [weak self] in self?.notice($0) }
            controller.onClose = { [weak self] in self?.authenticationWindows.removeValue(forKey: id) }
            authenticationWindows[id] = controller; return controller.webView
        }
        if policy.isChat(url), let url { webView.load(URLRequest(url: url)); return nil }
        if let url, policy.decision(for: url, userInitiated: navigationAction.navigationType == .linkActivated) == .external {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let window, window.attachedSheet == nil else { completionHandler(); return }
        let alert = NSAlert(); alert.messageText = frame.securityOrigin.host; alert.informativeText = String(message.prefix(2000))
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let window, window.attachedSheet == nil else { completionHandler(false); return }
        let alert = NSAlert(); alert.messageText = frame.securityOrigin.host; alert.informativeText = String(message.prefix(2000))
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard type == .microphone,
              frame.isMainFrame,
              policy.isChat(frame.request.url),
              policy.isChat(webView.url),
              origin.protocol.lowercased() == "https",
              NavigationPolicy.chatHosts.contains(origin.host.lowercased()) else {
            notice("Camera access and microphone requests outside ChatGPT are blocked.")
            decisionHandler(.deny)
            return
        }
        // Let WebKit and macOS display and remember the normal microphone permission prompt.
        // ChatPretzel never starts recording on its own; this callback follows a website request.
        decisionHandler(.prompt)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !effectiveSafeMode, message.webView === webView, message.frameInfo.isMainFrame,
              policy.allowsAdapter(message.frameInfo.request.url), policy.allowsAdapter(webView.url),
              let parsed = AdapterMessage.parse(message.body) else { return }
        switch parsed {
        case .privacyBoundary:
            drafts.removeAll(); navigationGeneration &+= 1; attachments.navigationChanged()
        case .draft(let href, let doc, let text, let temporary):
            guard href == webView.url?.absoluteString, doc == knownDocumentID else { return }
            drafts.put(href: href, text: text, isTemporary: temporary)
        }
    }
}
