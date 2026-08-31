import Carbon
import Foundation

@MainActor
final class ShortcutController {
    var onShortcut: (() -> Void)?

    var isRegistered: Bool {
        registeredShortcut != nil && hotKeyReference != nil
    }

    private var hotKeyReference: EventHotKeyRef?
    private var handlerReference: EventHandlerRef?
    private var registeredShortcut: ShortcutConfiguration?

    @discardableResult
    func register(_ shortcut: ShortcutConfiguration) -> Bool {
        if registeredShortcut == shortcut {
            return true
        }

        if handlerReference == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )

            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            let installStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                Self.eventHandler,
                1,
                &eventType,
                context,
                &handlerReference
            )

            guard installStatus == noErr else {
                handlerReference = nil
                GetKbdLog.error("shortcut.register.failed", "InstallEventHandler status \(installStatus)")
                return false
            }
        }

        var newHotKeyReference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x474B4244), id: 1)
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &newHotKeyReference
        )

        guard registerStatus == noErr, let newHotKeyReference else {
            if registeredShortcut == nil {
                RemoveEventHandler(handlerReference)
                handlerReference = nil
            }
            GetKbdLog.error("shortcut.register.failed", "RegisterEventHotKey status \(registerStatus)")
            return false
        }

        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        hotKeyReference = newHotKeyReference
        registeredShortcut = shortcut
        return true
    }

    func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }

        if let handlerReference {
            RemoveEventHandler(handlerReference)
            self.handlerReference = nil
        }

        registeredShortcut = nil
    }

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }

        var hotKeyID = EventHotKeyID(signature: 0, id: 0)
        var actualType: EventParamType = 0
        var actualSize = MemoryLayout<EventHotKeyID>.size
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            &actualType,
            MemoryLayout<EventHotKeyID>.size,
            &actualSize,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.signature == OSType(0x474B4244), hotKeyID.id == 1 else {
            return noErr
        }

        let controller = Unmanaged<ShortcutController>
            .fromOpaque(userData)
            .takeUnretainedValue()
        Task { @MainActor in
            controller.onShortcut?()
        }

        return noErr
    }
}
