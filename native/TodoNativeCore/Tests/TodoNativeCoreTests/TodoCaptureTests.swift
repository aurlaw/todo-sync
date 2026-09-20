import Foundation
import SwiftData
import Testing
@testable import TodoNativeCore

@Suite("TodoCapture: single-line text")
struct CaptureTextTests {
    @Test("trims the input into the title")
    func trims() {
        #expect(TodoCapture.draft(text: "  buy milk \n") == CaptureDraft(title: "buy milk"))
    }

    @Test("empty and whitespace-only input is not a capture")
    func empty() {
        #expect(TodoCapture.draft(text: "") == nil)
        #expect(TodoCapture.draft(text: " \n\t ") == nil)
    }
}

@Suite("TodoCapture: share input")
struct CaptureShareTests {
    private let page = URL(string: "https://example.com/articles/one")!

    @Test("shared text becomes the title and the URL becomes the note")
    func textAndURL() {
        let draft = TodoCapture.draft(sharedText: "  read this  ", url: page, pageTitle: "Page Title")
        #expect(draft == CaptureDraft(title: "read this", notes: "https://example.com/articles/one"))
    }

    @Test("text that is only the URL falls through to the page title")
    func urlOnlyTextUsesPageTitle() {
        let draft = TodoCapture.draft(sharedText: page.absoluteString, url: page, pageTitle: "Page Title")
        #expect(draft == CaptureDraft(title: "Page Title", notes: page.absoluteString))
    }

    @Test("no text and no page title falls back to the URL host")
    func hostFallback() {
        let draft = TodoCapture.draft(sharedText: nil, url: page, pageTitle: "  ")
        #expect(draft == CaptureDraft(title: "example.com", notes: page.absoluteString))
    }

    @Test("a link shared as plain text is treated as the URL, not the title")
    func bareURLText() {
        let draft = TodoCapture.draft(sharedText: "https://example.com/x", url: nil, pageTitle: nil)
        #expect(draft == CaptureDraft(title: "example.com", notes: "https://example.com/x"))
    }

    @Test("text without a URL has no notes")
    func textOnly() {
        #expect(TodoCapture.draft(sharedText: "call the dentist", url: nil, pageTitle: nil) == CaptureDraft(title: "call the dentist"))
    }

    @Test("only the first line of shared text is the title; the rest goes in the notes above the URL")
    func multiLine() {
        let draft = TodoCapture.draft(sharedText: "Plan trip\n\nbook flights\nfind hotel", url: page, pageTitle: nil)
        #expect(draft == CaptureDraft(title: "Plan trip", notes: "book flights\nfind hotel\n\nhttps://example.com/articles/one"))
    }

    @Test("nothing usable is not a capture")
    func nothing() {
        #expect(TodoCapture.draft(sharedText: nil, url: nil, pageTitle: nil) == nil)
        #expect(TodoCapture.draft(sharedText: "  \n", url: nil, pageTitle: "  ") == nil)
    }

    @Test("a non-web string is text, not a URL")
    func notAWebURL() {
        let draft = TodoCapture.draft(sharedText: "tel:5551234", url: nil, pageTitle: nil)
        #expect(draft == CaptureDraft(title: "tel:5551234"))
    }
}

@Suite("TodoCapture: save")
struct CaptureSaveTests {
    @Test("goes through TodoStore.create: dirty, stamped, at the end of the list")
    @MainActor
    func saves() throws {
        let container = try TodoContainer.make(inMemory: true)
        let store = TodoStore(context: container.mainContext)
        let first = try store.create(title: "existing")

        let item = try TodoCapture.save(CaptureDraft(title: "captured", notes: "n"), using: store)

        #expect(item.title == "captured")
        #expect(item.notes == "n")
        #expect(item.dirty)
        #expect(item.sortOrder == first.sortOrder + 1)
    }
}
