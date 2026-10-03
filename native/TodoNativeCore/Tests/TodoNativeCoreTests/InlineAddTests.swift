import Testing
@testable import TodoNativeCore

@Suite("InlineAdd")
struct InlineAddTests {
    @Test("plain text is saved as typed")
    func plainText() {
        #expect(InlineAdd.submit("Buy milk") == .save("Buy milk"))
    }

    @Test("leading and trailing whitespace and newlines are trimmed")
    func trims() {
        #expect(InlineAdd.submit("  Buy milk \t") == .save("Buy milk"))
        #expect(InlineAdd.submit("\nBuy milk\n") == .save("Buy milk"))
    }

    @Test("an empty field ends the session")
    func empty() {
        #expect(InlineAdd.submit("") == .end)
    }

    @Test("a whitespace-only field ends the session")
    func whitespaceOnly() {
        #expect(InlineAdd.submit("   ") == .end)
        #expect(InlineAdd.submit(" \t\n ") == .end)
    }

    @Test("whitespace inside the title is preserved")
    func internalWhitespace() {
        #expect(InlineAdd.submit(" Buy  two   things ") == .save("Buy  two   things"))
    }
}
