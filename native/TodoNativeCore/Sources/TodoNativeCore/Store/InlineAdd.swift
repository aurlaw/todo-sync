import Foundation

/// The inline add row's submit rule: what Return (or losing focus) does with the typed text.
public enum InlineAdd {
    public enum Submission: Equatable, Sendable {
        /// Save an item with this title, already trimmed.
        case save(String)
        /// Nothing to save: end the session.
        case end
    }

    /// Trims surrounding whitespace and newlines; whitespace inside the title is kept.
    public static func submit(_ text: String) -> Submission {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? .end : .save(title)
    }
}
