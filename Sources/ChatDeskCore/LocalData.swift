import Foundation

public struct LibraryEntry: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case prompt, bookmark, note, draft }
    public var id: UUID
    public var kind: Kind
    public var title: String
    public var text: String
    public var tags: String
    public var url: String?
    public var updatedAt: Date
    public init(kind: Kind, title: String, text: String = "", tags: String = "", url: String? = nil) {
        id = UUID(); self.kind = kind; self.title = title; self.text = text
        self.tags = tags; self.url = url; updatedAt = Date()
    }
}
public struct LibraryDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var entries: [LibraryEntry] = []
    public init(entries: [LibraryEntry] = []) { self.entries = entries }
    public func validate() throws {
        guard schemaVersion == 1 else { throw StoreFailure.unsupportedVersion }
        guard entries.count <= 500, Set(entries.map(\.id)).count == entries.count else { throw StoreFailure.invalidData }
        for e in entries {
            guard e.title.utf8.count <= 1024, e.text.utf8.count <= 65_536, e.tags.utf8.count <= 2048,
                  e.url == nil || (e.url!.utf8.count <= 4096 && NavigationPolicy().isChat(URL(string: e.url!))) else {
                throw StoreFailure.invalidData
            }
        }
    }
}
public enum StoreFailure: Error, Equatable { case unsupportedVersion, invalidData, fileTooLarge, corrupt }

/// Small, atomic, versioned store. Caller serializes I/O and must not replace a corrupt store with defaults.
public struct LibraryStore {
    public let url: URL
    public static let maximumBytes = 5 * 1024 * 1024
    public init(url: URL) { self.url = url }
    public func load() throws -> LibraryDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibraryDocument() }
        return try Self.decode(Self.readBounded(url))
    }
    public static func readBounded(_ url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw StoreFailure.fileTooLarge }
        return data
    }
    public static func decode(_ data: Data) throws -> LibraryDocument {
        guard data.count <= maximumBytes else { throw StoreFailure.fileTooLarge }
        let document: LibraryDocument
        do { document = try JSONDecoder().decode(LibraryDocument.self, from: data) }
        catch { throw StoreFailure.corrupt }
        try document.validate()
        return document
    }
    public static func encode(_ document: LibraryDocument) throws -> Data {
        try document.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= maximumBytes else { throw StoreFailure.fileTooLarge }
        return data
    }
    public func save(_ document: LibraryDocument) throws {
        let bytes = try Self.encode(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: url.path) {
            let prior = try Self.readBounded(url)
            _ = try Self.decode(prior) // Never silently destroy corrupt/unknown-version data.
            try prior.write(to: url.appendingPathExtension("backup"), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.appendingPathExtension("backup").path)
        }
        try bytes.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Session-only drafts. No disk writes and NO automatic restore across accounts or navigation.
public struct DraftBuffer: Sendable {
    public struct Draft: Equatable, Sendable { public let href: String; public let text: String; public let savedAt: Date }
    private var values: [String: Draft] = [:]
    public let capacity: Int
    public init(capacity: Int = 20) { self.capacity = max(1, capacity) }
    public mutating func put(href: String, text: String, isTemporary: Bool, now: Date = Date()) {
        guard !isTemporary, NavigationPolicy().isChat(URL(string: href)), text.utf8.count <= 65_536 else { return }
        if text.isEmpty { values.removeValue(forKey: href); return }
        values[href] = Draft(href: href, text: text, savedAt: now)
        while values.count > capacity, let oldest = values.min(by: { $0.value.savedAt < $1.value.savedAt })?.key {
            values.removeValue(forKey: oldest)
        }
    }
    public func draft(for href: String) -> Draft? { values[href] }
    public mutating func removeAll() { values.removeAll(keepingCapacity: false) }
    public var count: Int { values.count }
}
