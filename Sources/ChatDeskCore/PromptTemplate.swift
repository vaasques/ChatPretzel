import Foundation

public enum PromptTemplate {
    public static func variables(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{([\p{L}\p{N}_ -]{1,60})\}\}"#) else { return [] }
        var seen = Set<String>()
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range(at: 1), in: text) else { return nil }
            let key = String(text[range]); return seen.insert(key).inserted ? key : nil
        }
    }
    public static func render(_ text: String, values: [String: String]) -> String {
        // One pass: values are data, not templates. A value containing {{other}} is not expanded again.
        guard let regex = try? NSRegularExpression(pattern: #"\{\{([\p{L}\p{N}_ -]{1,60})\}\}"#) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let keyRange = Range(match.range(at: 1), in: text), let range = Range(match.range, in: result),
                  let value = values[String(text[keyRange])] else { continue }
            result.replaceSubrange(range, with: value)
        }
        return result
    }
}
