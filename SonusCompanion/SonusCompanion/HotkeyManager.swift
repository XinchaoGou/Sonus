import Carbon
import Foundation

struct HotkeyConfiguration: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = HotkeyConfiguration(keyCode: UInt32(kVK_Escape), carbonModifiers: UInt32(optionKey))

    var displayName: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeDisplayName(keyCode))
        return parts.joined()
    }

    private func keyCodeDisplayName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Escape: return "Esc"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        default:
            if let scalar = keyCodeToCharacter(code) {
                return String(scalar).uppercased()
            }
            return "Key \(code)"
        }
    }

    private func keyCodeToCharacter(_ code: UInt32) -> Character? {
        let map: [UInt32: Character] = [
            UInt32(kVK_ANSI_A): "a", UInt32(kVK_ANSI_B): "b", UInt32(kVK_ANSI_C): "c",
            UInt32(kVK_ANSI_D): "d", UInt32(kVK_ANSI_E): "e", UInt32(kVK_ANSI_F): "f",
            UInt32(kVK_ANSI_G): "g", UInt32(kVK_ANSI_H): "h", UInt32(kVK_ANSI_I): "i",
            UInt32(kVK_ANSI_J): "j", UInt32(kVK_ANSI_K): "k", UInt32(kVK_ANSI_L): "l",
            UInt32(kVK_ANSI_M): "m", UInt32(kVK_ANSI_N): "n", UInt32(kVK_ANSI_O): "o",
            UInt32(kVK_ANSI_P): "p", UInt32(kVK_ANSI_Q): "q", UInt32(kVK_ANSI_R): "r",
            UInt32(kVK_ANSI_S): "s", UInt32(kVK_ANSI_T): "t", UInt32(kVK_ANSI_U): "u",
            UInt32(kVK_ANSI_V): "v", UInt32(kVK_ANSI_W): "w", UInt32(kVK_ANSI_X): "x",
            UInt32(kVK_ANSI_Y): "y", UInt32(kVK_ANSI_Z): "z",
        ]
        return map[code]
    }
}

private func sonusFourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + FourCharCode(scalar.value)
    }
    return result
}

@MainActor
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: sonusFourCharCode("SNUS"), id: 1)
    var onHotkey: (() -> Void)?

    func register(configuration: HotkeyConfiguration) {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKey = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKey
                )
                guard status == noErr, hotKey.signature == sonusFourCharCode("SNUS") else {
                    return OSStatus(eventNotHandledErr)
                }
                Task { @MainActor in
                    manager.onHotkey?()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            configuration.keyCode,
            configuration.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
            AppLogger.log("hotkey registered: \(configuration.displayName)")
        } else {
            AppLogger.log("hotkey registration failed status=\(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
