import Foundation

enum AppResources {
    static func url(_ filename: String) -> URL? {
        // A packaged app uses explicit assets, avoiding SwiftPM's absolute build-path fallback.
        if let root = Bundle.main.resourceURL?.appendingPathComponent("ChatDeskAssets", isDirectory: true) {
            let candidate = root.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Resources")
    }
    static func text(_ filename: String) throws -> String {
        guard let url = url(filename) else { throw CocoaError(.fileNoSuchFile) }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
