import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

struct SendShortcut: Codable, Equatable, Sendable {
    struct Modifiers: OptionSet, Codable, Equatable, Sendable {
        let rawValue: UInt32

        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    let keyCode: UInt32
    let key: String
    let modifiers: Modifiers

    var displayName: String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        return value + key.uppercased()
    }
}

@MainActor
@Observable
final class ShortcutManager {
    private(set) var shortcut: SendShortcut?
    private(set) var registrationError: String?
    private(set) var isRegistered = false
    var onTrigger: (() -> Void)?

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private let defaultsKey = "FusionSpatial.SendShortcut"
    private let hotKeyID = EventHotKeyID(signature: 0x46535054, id: 1) // FSPT

    static let defaultShortcut = SendShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        key: "V",
        modifiers: [.control, .option]
    )

    init() {
        shortcut = loadShortcut()
        installEventHandler()
    }

    @discardableResult
    func register() -> Bool {
        unregister()
        registrationError = nil
        guard let shortcut else { return true }

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers(for: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            registrationError = "快捷键不可用 · Shortcut unavailable"
            return false
        }
        hotKeyReference = reference
        isRegistered = true
        return true
    }

    func unregister() {
        if let hotKeyReference { UnregisterEventHotKey(hotKeyReference) }
        hotKeyReference = nil
        isRegistered = false
    }

    @discardableResult
    func updateShortcut(_ newShortcut: SendShortcut?) -> Bool {
        let previous = shortcut
        shortcut = newShortcut
        if register() {
            saveShortcut()
            return true
        }

        shortcut = previous
        _ = register()
        registrationError = "快捷键不可用 · Shortcut unavailable"
        return false
    }

    func loadShortcut() -> SendShortcut? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return Self.defaultShortcut
        }
        return (try? JSONDecoder().decode(SendShortcut.self, from: data)) ?? Self.defaultShortcut
    }

    func saveShortcut() {
        guard let shortcut else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func shortcut(from event: NSEvent) -> Result<SendShortcut, ShortcutValidationError> {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: SendShortcut.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        guard !modifiers.isEmpty else { return .failure(.modifierRequired) }

        let key = keyName(for: event)
        guard event.keyCode != UInt16(kVK_Escape) else { return .failure(.ordinaryKeyRequired) }

        let commandOnly = modifiers == .command
        let protectedKeys = ["Q", "W", "H", "C", "V", "X", "A"]
        guard !(commandOnly && protectedKeys.contains(key)) else { return .failure(.systemShortcut) }

        return .success(SendShortcut(keyCode: UInt32(event.keyCode), key: key, modifiers: modifiers))
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var receivedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &receivedID
            )
            guard status == noErr, receivedID.signature == 0x46535054, receivedID.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in manager.handleHotKey() }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
    }

    private func handleHotKey() {
        onTrigger?()
    }

    private func carbonModifiers(for modifiers: SendShortcut.Modifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    private func keyName(for event: NSEvent) -> String {
        let explicit: [UInt16: String] = [
            UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
            UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
            UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
            UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
            UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
            UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
            UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
            UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
            UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
            UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
            UInt16(kVK_ANSI_9): "9",
            UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12"
        ]
        return explicit[event.keyCode] ?? "Key \(event.keyCode)"
    }
}

enum ShortcutValidationError: LocalizedError {
    case modifierRequired
    case ordinaryKeyRequired
    case systemShortcut

    var errorDescription: String? {
        switch self {
        case .modifierRequired: "请同时按下至少一个修饰键 · Add at least one modifier"
        case .ordinaryKeyRequired: "请按修饰键和普通按键 · Press a modifier and a key"
        case .systemShortcut: "该组合是 macOS 标准快捷键 · Reserved by macOS"
        }
    }
}
