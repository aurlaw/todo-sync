#if os(macOS)
import AppKit
import Carbon.HIToolbox
import OSLog
import SwiftData
import SwiftUI
import TodoNativeCore

/// macOS quick capture: owns the store used by the menu-bar popover and the hotkey panel, and the
/// global hotkey itself. Runs in the main app process, so a capture syncs through the app's own
/// coordinator (about two seconds later) with no cross-process step.
@MainActor
final class QuickCapture {
    private static let log = Logger(subsystem: "com.aurlaw.TodoNative", category: "capture")

    private let store: TodoStore
    private var panel: CapturePanel?
    private var hotkey: GlobalHotkey?

    init(context: ModelContext, coordinator: SyncCoordinator) {
        store = TodoStore(context: context, onMutation: { [coordinator] in coordinator.scheduleSync() })
        // ⌃⌥Space. Failure is logged by `GlobalHotkey`; the menu-bar item still works.
        hotkey = GlobalHotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.togglePanel()
        }
    }

    /// Returns whether the text was saved.
    func capture(_ text: String) -> Bool {
        guard let draft = TodoCapture.draft(text: text) else { return false }
        do {
            try TodoCapture.save(draft, using: store)
            return true
        } catch {
            Self.log.error("capture failed: \(String(describing: error))")
            return false
        }
    }

    /// Closes the menu-bar popover after a save. `MenuBarExtra` has no dismiss API, so this orders out the
    /// window that has key focus at the time. [NEEDS VERIFICATION] that the popover reappears on the next click.
    func dismissMenuBarPopover() {
        NSApp.keyWindow?.orderOut(nil)
    }

    private func togglePanel() {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        let panel = CapturePanel()
        let field = CaptureField(
            capture: { [weak self] in self?.capture($0) ?? false },
            dismiss: { [weak self] in self?.closePanel() }
        )
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        panel.contentView = NSHostingView(rootView: field)
        panel.setContentSize(panel.contentView?.fittingSize ?? CGSize(width: 420, height: 52))
        panel.onResignKey = { [weak self] in self?.closePanel() }
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    private func closePanel() {
        panel?.onResignKey = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Horizontally centred, in the upper third of the screen the pointer is on.
    private func position(_ panel: CapturePanel) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(x: frame.midX - size.width / 2, y: frame.maxY - frame.height / 3 - size.height / 2))
    }
}

/// A borderless, non-activating panel: it takes keyboard focus for typing without bringing the main
/// window forward or pulling focus away from the app the user was in.
final class CapturePanel: NSPanel {
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func cancelOperation(_ sender: Any?) {
        onResignKey?()
    }
}
#endif
