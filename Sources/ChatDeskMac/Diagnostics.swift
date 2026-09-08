import AppKit
import Foundation

extension MainWindowController {
    /// Explicit export; no tokens, page URLs, prompts, filenames, paths or user identifiers.
    func exportDiagnostics() {
        guard let window, window.attachedSheet == nil else { return }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        var counts: [String: Int] = [:]
        for record in attachments.records { counts[record.state.rawValue, default: 0] += 1 }
        let report: [String: Any] = [
            "app": "ChatPretzel", "version": "0.1.3-local", "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "buildID": Bundle.main.object(forInfoDictionaryKey: "ChatDeskBuildID") as? String ?? "source-development",
            "architecture": architecture, "safeMode": effectiveSafeMode, "fixtureMode": fixtureMode,
            "assistedPaste": preferences.assistedPaste, "attachmentStates": counts,
            "transferInProgress": attachments.isBusy, "liveCompatibility": "NOT AUTOMATICALLY VERIFIED",
            "totalRAMAndCPU": "NOT MEASURED BY THIS EXPORT; use the documented Instruments procedure",
            "source": "User-initiated, content-free diagnostic export"
        ]
        let panel = NSSavePanel(); panel.nameFieldStringValue = "ChatPretzel-diagnostik.json"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url, options: .atomic); self?.notice("Teknisk diagnostik sparad utan chattinnehåll eller filnamn.")
            } catch { self?.notice("Diagnostiken kunde inte sparas.") }
        }
    }
}
