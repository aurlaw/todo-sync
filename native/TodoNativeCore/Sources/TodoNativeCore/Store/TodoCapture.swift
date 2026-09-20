import Foundation

/// What a capture surface (menu-bar field, hotkey panel, Share extension) hands to `TodoStore.create`.
public struct CaptureDraft: Equatable, Sendable {
    public var title: String
    public var notes: String?

    public init(title: String, notes: String? = nil) {
        self.title = title
        self.notes = notes
    }
}

/// Turns raw captured input into a `CaptureDraft` and saves it. Every capture path goes through
/// here, so this is the one place N5's `TitleDateParser` will hook in (run it over the title in
/// `save`, before `create`, and set `dueAt` from the result).
public enum TodoCapture {
    /// A single line typed into the menu-bar field or hotkey panel. Empty or whitespace-only input
    /// is not a capture.
    public static func draft(text: String) -> CaptureDraft? {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : CaptureDraft(title: title)
    }

    /// Input from the Share sheet, where any of the three pieces may be missing.
    ///
    /// The title is the shared text, else the page title, else the URL's host. Only the first line of
    /// shared text becomes the title; any further lines, then the URL, go in the notes. Text that is
    /// nothing but the URL does not count as shared text.
    public static func draft(sharedText: String?, url: URL?, pageTitle: String?) -> CaptureDraft? {
        var url = url
        var text = clean(sharedText)
        // Some apps share a link as plain text; treat a bare web address as the URL, not the title.
        if url == nil, let candidate = text, let parsed = bareWebURL(candidate) {
            url = parsed
            text = nil
        }
        if let url, text == url.absoluteString { text = nil }

        var lines = text?.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
        let title: String
        if !lines.isEmpty {
            title = lines.removeFirst()
        } else if let pageTitle = clean(pageTitle) {
            title = pageTitle
        } else if let host = url?.host(), !host.isEmpty {
            title = host
        } else {
            return nil
        }

        var noteParts: [String] = []
        if !lines.isEmpty { noteParts.append(lines.joined(separator: "\n")) }
        if let url { noteParts.append(url.absoluteString) }
        return CaptureDraft(title: title, notes: noteParts.isEmpty ? nil : noteParts.joined(separator: "\n\n"))
    }

    @MainActor
    @discardableResult
    public static func save(_ draft: CaptureDraft, using store: TodoStore) throws -> TodoItem {
        try store.create(title: draft.title, notes: draft.notes)
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func bareWebURL(_ text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil
        else { return nil }
        return url
    }
}
