import Foundation
import Testing
@testable import TodoNativeCore

@Suite("DeepLink")
struct DeepLinkTests {
    private let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    @Test("parses each destination")
    func parses() {
        #expect(DeepLink(url: URL(string: "todonative://today")!) == .today)
        #expect(DeepLink(url: URL(string: "todonative://new")!) == .new)
        #expect(DeepLink(url: URL(string: "todonative://item/3f2504e0-4f89-11d3-9a0c-0305e82c3301")!) == .item(id))
    }

    @Test("a trailing slash and an upper-case scheme or host still parse")
    func lenient() {
        #expect(DeepLink(url: URL(string: "todonative://today/")!) == .today)
        #expect(DeepLink(url: URL(string: "TODONATIVE://Today")!) == .today)
    }

    @Test("every link round-trips through its URL, with a lowercase id")
    func roundTrip() {
        for link in [DeepLink.today, .new, .item(id)] {
            #expect(DeepLink(url: link.url) == link)
        }
        #expect(DeepLink.item(id).url.absoluteString == "todonative://item/3f2504e0-4f89-11d3-9a0c-0305e82c3301")
    }

    @Test("rejects a malformed id, an unknown destination, extra path, a missing id and another scheme")
    func rejects() {
        #expect(DeepLink(url: URL(string: "todonative://item/not-a-uuid")!) == nil)
        #expect(DeepLink(url: URL(string: "todonative://item")!) == nil)
        #expect(DeepLink(url: URL(string: "todonative://item/3f2504e0-4f89-11d3-9a0c-0305e82c3301/extra")!) == nil)
        #expect(DeepLink(url: URL(string: "todonative://archive")!) == nil)
        #expect(DeepLink(url: URL(string: "todonative://today/extra")!) == nil)
        #expect(DeepLink(url: URL(string: "https://today")!) == nil)
        #expect(DeepLink(url: URL(string: "todonative:")!) == nil)
    }
}
