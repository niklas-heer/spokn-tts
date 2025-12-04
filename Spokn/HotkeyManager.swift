import AppKit
import Carbon

/// Manages global hotkey registration
final class HotkeyManager {

    typealias HotkeyHandler = () -> Void

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var callback: HotkeyHandler?

    // Singleton for the callback to access
    private static var shared: HotkeyManager?

    init() {
        HotkeyManager.shared = self
    }

    deinit {
        unregister()
    }

    /// Register a global hotkey
    /// - Parameters:
    ///   - keyCode: The virtual key code
    ///   - modifiers: The modifier flags (command, option, etc.)
    ///   - handler: Closure to call when hotkey is pressed
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping HotkeyHandler) {
        self.callback = handler

        // Define the hotkey event type
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        // Install the event handler
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                HotkeyManager.shared?.callback?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard status == noErr else {
            print("Failed to install event handler: \(status)")
            return
        }

        // Register the hotkey
        let hotkeyID = EventHotKeyID(
            signature: OSType(0x5350_4B4E),  // "SPKN" for Spokn
            id: 1
        )

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            print("Failed to register hotkey: \(registerStatus)")
        }
    }

    /// Unregister the hotkey
    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    // MARK: - Convenience

    /// Common modifier combinations
    struct Modifiers {
        static let command: UInt32 = UInt32(cmdKey)
        static let option: UInt32 = UInt32(optionKey)
        static let control: UInt32 = UInt32(controlKey)
        static let shift: UInt32 = UInt32(shiftKey)
    }

    /// Common key codes
    struct KeyCodes {
        static let s: UInt32 = 0x01
        static let r: UInt32 = 0x0F
        static let t: UInt32 = 0x11
        static let space: UInt32 = 0x31
    }
}
