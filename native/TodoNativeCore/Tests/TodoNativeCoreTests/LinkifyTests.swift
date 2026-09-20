import Foundation
import Testing
@testable import TodoNativeCore

@Suite("Linkify")
struct LinkifyTests {
    /// The text of each run paired with its link, so a test can read the result as (text, url) pieces.
    private func pieces(_ text: String) -> [(text: String, url: URL?)] {
        let attributed = Linkify.attributed(text)
        return attributed.runs.map { (String(attributed[$0.range].characters), $0.link) }
    }

    @Test("a web address becomes a link and the text around it is untouched")
    func linkInSentence() {
        let result = pieces("see https://example.com/a?b=1 for details")

        #expect(result.map(\.text) == ["see ", "https://example.com/a?b=1", " for details"])
        #expect(result.map(\.url) == [nil, URL(string: "https://example.com/a?b=1"), nil])
    }

    @Test("a note that is only a link (what the Share extension saves) is one link")
    func onlyLink() {
        let result = pieces("https://example.com/articles/one")

        #expect(result.count == 1)
        #expect(result[0].url == URL(string: "https://example.com/articles/one"))
    }

    @Test("several links, with notes text between them")
    func multipleLinks() {
        let result = pieces("first line\n\nhttps://a.example\nhttps://b.example")

        #expect(result.compactMap(\.url) == [URL(string: "https://a.example")!, URL(string: "https://b.example")!])
        #expect(result.map(\.text).joined() == "first line\n\nhttps://a.example\nhttps://b.example")
    }

    @Test("a bare www address gets a scheme")
    func wwwGetsScheme() {
        let result = pieces("www.example.com")

        #expect(result.first?.url?.host() == "www.example.com")
    }

    @Test("text without a link has no link and is unchanged")
    func plainText() {
        let attributed = Linkify.attributed("buy milk and eggs")

        #expect(String(attributed.characters) == "buy milk and eggs")
        #expect(attributed.runs.allSatisfy { $0.link == nil })
    }

    @Test("empty text is empty")
    func empty() {
        #expect(Linkify.attributed("").characters.isEmpty)
    }
}
