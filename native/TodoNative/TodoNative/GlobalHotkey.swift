#if os(macOS)
import Carbon.HIToolbox
import OSLog

/// A system-wide hotkey through Carbon's `RegisterEventHotKey`. Unlike an `NSEvent` global monitor or a
/// `CGEventTap`, it needs no Accessibility or Input Monitoring permission and consumes the key press.
/// Whether it works inside the App Sandbox is the point of the N7a spike: watch the log with
/// `log stream --predicate 'subsystem == "com.aurlaw.TodoNative"'`.
@MainActor
final class GlobalHotkey {
    private static let log = Logger(subsystem: "com.aurlaw.TodoNative", category: "hotkey")

    fileprivate let onPress: @MainActor () -> Void
    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    /// `nil` if the handler or the hotkey could not be registered (for example another app owns the combination).
    init?(keyCode: UInt32, modifiers: UInt32, onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else {
            Self.log.error("InstallEventHandler failed: \(installStatus)")
            return nil
        }

        let signature = "TDNV".utf8.reduce(OSType(0)) { ($0 << 8) + OSType($1) }
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            Self.log.error("RegisterEventHotKey failed: \(registerStatus)")
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
        Self.log.info("hotkey registered")
    }
}

/// The hotkey event arrives on the main thread through the application event target.
private nonisolated func hotkeyEventHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotkey.onPress() }
    return noErr
}
#endif
