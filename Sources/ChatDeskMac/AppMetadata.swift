import Foundation

enum AppMetadata {
    static var name: String {
        nonEmptyBundleValue(for: "CFBundleDisplayName")
            ?? nonEmptyBundleValue(for: "CFBundleName")
            ?? "ChatPretzel"
    }

    static var version: String {
        nonEmptyBundleValue(for: "CFBundleShortVersionString") ?? "development"
    }

    static var versionedName: String { "\(name) \(version)" }

    private static func nonEmptyBundleValue(for key: String) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
