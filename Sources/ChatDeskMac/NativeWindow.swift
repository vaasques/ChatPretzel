import AppKit
import WebKit
import ChatDeskCore

final class ChatWindow: NSWindow {
    var interceptFilePaste: (() -> Bool)?
    var mapControlCV: (() -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags == [.command], key == "v", interceptFilePaste?() == true { return true }
        if flags == [.control], mapControlCV?() == true {
            if key == "v" {
                if interceptFilePaste?() == true { return true }
                return NSApp.sendAction(Selector(("paste:")), to: nil, from: self)
            }
            if key == "c" { return NSApp.sendAction(Selector(("copy:")), to: nil, from: self) }
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class NativeWebView: WKWebView {
    var onFileDrop: ((FileSelection) -> Bool)?
    var mayHandleDrop: (() -> Bool)?
    var onUnsupportedDrop: ((String) -> Void)?
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if mayHandleDrop?() == true, sender.draggingPasteboard.types?.contains(.fileURL) == true { return .copy }
        return super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if mayHandleDrop?() == true, sender.draggingPasteboard.types?.contains(.fileURL) == true { return .copy }
        return super.draggingUpdated(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard mayHandleDrop?() == true else { return super.performDragOperation(sender) }
        switch ClipboardReader.read(sender.draggingPasteboard) {
        case .files(let selection): return onFileDrop?(selection) ?? false
        case .unsupported(let message): onUnsupportedDrop?(message); return false
        case .useSystemPaste: return super.performDragOperation(sender)
        }
    }
}

final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
