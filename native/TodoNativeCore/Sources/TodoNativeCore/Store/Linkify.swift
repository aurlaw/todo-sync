import Foundation

/// Makes the web addresses in free text tappable. Notes are stored as plain text (the Share extension
/// puts a shared link there), so links are found at display time rather than stored.
public enum Linkify {
    public static func attributed(_ text: String) -> AttributedString {
        // Created per call: `NSDataDetector` is not `Sendable`, and notes are short.
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return AttributedString(text)
        }
        var result = AttributedString()
        var cursor = text.startIndex
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let range = Range(match.range, in: text), range.lowerBound >= cursor else { continue }
            result += AttributedString(text[cursor..<range.lowerBound])
            var link = AttributedString(text[range])
            link.link = url
            result += link
            cursor = range.upperBound
        }
        result += AttributedString(text[cursor...])
        return result
    }
}
