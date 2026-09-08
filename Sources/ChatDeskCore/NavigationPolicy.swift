import Foundation

/// Policy for top-level documents. This is deliberately NOT a resource/CDN filter.
/// Only a chat document (or the one bundled test fixture) may use the native adapter.
public struct NavigationPolicy: Sendable {
    public enum Decision: Equatable { case embedded, external, deny }
    public let fixtureURL: URL?
    public init(fixtureURL: URL? = nil) { self.fixtureURL = fixtureURL?.standardizedFileURL }
    public static let chatHosts: Set<String> = ["chatgpt.com", "chat.openai.com"]
    public static let authenticationHosts: Set<String> = [
        "auth.openai.com", "auth0.openai.com", "accounts.google.com",
        "appleid.apple.com", "account.apple.com", "idmsa.apple.com",
        "login.microsoftonline.com", "login.live.com"
    ]
    public func isChat(_ url: URL?) -> Bool {
        guard let url, url.user == nil, url.password == nil,
              url.scheme?.lowercased() == "https", url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return false }
        return Self.chatHosts.contains(host)
    }
    public func isAuthentication(_ url: URL?) -> Bool {
        guard let url, url.user == nil, url.password == nil,
              url.scheme?.lowercased() == "https", url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return false }
        return Self.authenticationHosts.contains(host)
    }
    public func isFixture(_ url: URL?) -> Bool {
        guard let fixtureURL, let url, url.isFileURL, url.user == nil, url.password == nil,
              url.host == nil || url.host == "" || url.host?.lowercased() == "localhost" else { return false }
        return url.standardizedFileURL.path == fixtureURL.path
    }
    public func allowsAdapter(_ url: URL?) -> Bool { isChat(url) || isFixture(url) }
    public func isChatBlob(_ url: URL?) -> Bool {
        guard let url, url.scheme == "blob" else { return false }
        return isChat(URL(string: String(url.absoluteString.dropFirst(5))))
    }
    public func decision(for url: URL?, userInitiated: Bool, authenticationWindow: Bool = false) -> Decision {
        guard let url else { return .deny }
        if isFixture(url) || isChat(url) || isAuthentication(url) { return .embedded }
        if authenticationWindow && url.absoluteString == "about:blank" { return .embedded }
        guard userInitiated, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return .deny }
        return .external
    }
}

public struct PageIdentity: Codable, Equatable, Sendable {
    public let href: String
    public let documentID: String
    public let generation: UInt64
    public init(href: String, documentID: String, generation: UInt64) {
        self.href = href; self.documentID = documentID; self.generation = generation
    }
}

/// A capability created ONLY from a native user action. Never constructed by web messages.
public struct UploadPermit: Sendable {
    public enum Failure: Error, Equatable { case expired, wrongPage, alreadyConsumed, rejectedFrame }
    public let token: UUID
    public let page: PageIdentity
    public let deadline: Date
    public private(set) var consumed = false
    public init(page: PageIdentity, now: Date = Date(), lifetime: TimeInterval = 5) {
        token = UUID(); self.page = page; deadline = now.addingTimeInterval(lifetime)
    }
    public mutating func consume(page actual: PageIdentity, mainFrame: Bool, now: Date = Date()) throws {
        guard !consumed else { throw Failure.alreadyConsumed }
        guard now <= deadline else { throw Failure.expired }
        guard mainFrame else { throw Failure.rejectedFrame }
        guard actual == page else { throw Failure.wrongPage }
        consumed = true
    }
}
