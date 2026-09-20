//
//  ShareViewController.swift
//  TodoNativeShare
//
//  Created by Michael Lawrence on 9/20/26.
//

import SwiftData
import SwiftUI
import TodoNativeCore
import UIKit
import UniformTypeIdentifiers

/// Share extension: turns shared text or a web link into a todo in the App Group store.
///
/// It never syncs (no Keychain or Worker access here) and never creates the store: the item is written
/// `dirty`, and the main app pushes it the next time it becomes active.
final class ShareViewController: UIViewController {
    private var container: ModelContainer?

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await start() }
    }

    private func start() async {
        do {
            container = try TodoContainer.makeShared(migrateLegacyStore: false)
        } catch TodoContainerError.storeNotReady {
            show(MessageView(text: "Open TodoNative once to finish setup, then share again.", close: cancel))
            return
        } catch {
            show(MessageView(text: "Couldn't open the todo store: \(error)", close: cancel))
            return
        }

        let input = await loadInput()
        guard let draft = TodoCapture.draft(sharedText: input.text, url: input.url, pageTitle: input.pageTitle) else {
            show(MessageView(text: "There's nothing to add from this item.", close: cancel))
            return
        }
        show(ShareView(draft: draft, add: add, cancel: cancel))
    }

    // MARK: Loading

    private struct SharedInput {
        var text: String?
        var url: URL?
        var pageTitle: String?
    }

    /// Text comes from the plain-text attachment and the link from the URL attachment. The page title, when the
    /// host supplies one, arrives on the extension item itself. [NEEDS VERIFICATION] that Safari sets it.
    private func loadInput() async -> SharedInput {
        var input = SharedInput()
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            if input.pageTitle == nil {
                input.pageTitle = item.attributedTitle?.string ?? item.attributedContentText?.string
            }
            for provider in item.attachments ?? [] {
                if input.url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await load(NSURL.self, from: provider) as URL?, !url.isFileURL {
                        input.url = url
                    }
                } else if input.text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    input.text = await load(NSString.self, from: provider) as String?
                }
            }
        }
        return input
    }

    /// `NSItemProvider.loadObject` has no async form; nil means the provider could not supply the type.
    private func load<T: NSItemProviderReading>(_ type: T.Type, from provider: NSItemProvider) async -> T? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { object, _ in
                continuation.resume(returning: object as? T)
            }
        }
    }

    // MARK: Actions

    private func add(_ draft: CaptureDraft) {
        guard let container else { return cancel() }
        do {
            try TodoCapture.save(draft, using: TodoStore(context: container.mainContext))
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            show(MessageView(text: "Couldn't save the todo: \(error)", close: cancel))
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    // MARK: Hosting

    private func show<Content: View>(_ content: Content) {
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        let host = UIHostingController(rootView: content)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
