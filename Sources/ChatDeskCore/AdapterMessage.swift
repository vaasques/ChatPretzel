import Foundation

/// Native message validation is a second boundary. The message handler is also only installed
/// in an isolated WKContentWorld, and the caller verifies frame, current URL and document identity.
public enum AdapterMessage: Equatable {
    case draft(href: String, documentID: String, text: String, temporary: Bool)
    case privacyBoundary
    public static func parse(_ object: Any) -> AdapterMessage? {
        guard let dictionary = object as? [String: Any], let kind = dictionary["kind"] as? String else { return nil }
        switch kind {
        case "privacyBoundary": return .privacyBoundary
        case "draft":
            guard let href = dictionary["href"] as? String, href.utf8.count <= 4096,
                  let doc = dictionary["documentID"] as? String, doc.count <= 80, !doc.isEmpty,
                  let text = dictionary["text"] as? String, text.utf8.count <= 65_536,
                  let temporary = dictionary["temporary"] as? Bool else { return nil }
            return .draft(href: href, documentID: doc, text: text, temporary: temporary)
        default: return nil // There is intentionally no readFile, clipboard, shell or fetch message.
        }
    }
}
