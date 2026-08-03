import AppKit
import Carbon.HIToolbox

/// A process-wide hotkey that fires no matter which app is frontmost.
///
/// Carbon's `RegisterEventHotKey` is the only API that does this without
/// Accessibility trust and without an event tap. Ancient, and fine.
///
/// ⚠️ SPACE IS NOT AVAILABLE. macOS books every useful Space combination:
///     ⌘Space          Spotlight
///     ⌃Space          previous input source
///     ⌃⌥Space         next input source
///     ⌥⌘Space         Show Finder search window   ← we shipped this by mistake
///     ⌃⌘Space         emoji & symbols viewer
/// A global hotkey also outranks whatever the frontmost app wanted to do with
/// the same chord, so two-modifier combos (⌥⌘R and friends) silently break
/// that shortcut in every app on the machine. Hence the three-modifier default.
public final class HotKey {
    public struct Combo {
        public var keyCode: UInt32
        public var modifiers: UInt32
        public var display: String

        public init(keyCode: UInt32, modifiers: UInt32, display: String) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.display = display
        }

        /// ⌃⌥⌘N. Three modifiers so no app loses a shortcut to us, and not a
        /// system default. Override with ONARI_HOTKEY, e.g. "ctrl+opt+cmd+j".
        public static let `default` = Combo(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            display: "⌃⌥⌘N"
        )

        private static let keyCodes: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
            "9": kVK_ANSI_9, "0": kVK_ANSI_0,
            // Function keys are the safest of all — nothing else claims F13+.
            "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15,
            "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18, "f19": kVK_F19,
        ]

        private static let symbols: [String: String] = [
            "cmd": "⌘", "command": "⌘",
            "opt": "⌥", "option": "⌥", "alt": "⌥",
            "ctrl": "⌃", "control": "⌃",
            "shift": "⇧",
        ]

        /// Parse "ctrl+opt+cmd+n". Returns nil on anything unrecognized, so a
        /// typo in the env var falls back to the default instead of silently
        /// registering the wrong key.
        public static func parse(_ raw: String) -> Combo? {
            let parts = raw.lowercased()
                .split(separator: "+")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let keyName = parts.last, let code = keyCodes[keyName] else { return nil }

            var modifiers: UInt32 = 0
            var shown = ""
            for part in parts.dropLast() {
                switch part {
                case "cmd", "command": modifiers |= UInt32(cmdKey)
                case "opt", "option", "alt": modifiers |= UInt32(optionKey)
                case "ctrl", "control": modifiers |= UInt32(controlKey)
                case "shift": modifiers |= UInt32(shiftKey)
                default: return nil
                }
                shown += symbols[part] ?? ""
            }
            guard modifiers != 0 else { return nil }

            return Combo(
                keyCode: UInt32(code),
                modifiers: modifiers,
                display: shown + keyName.uppercased()
            )
        }

        /// `ONARI_HOTKEY` if set and parseable, otherwise the default.
        public static func fromEnvironment() -> Combo {
            guard let raw = ProcessInfo.processInfo.environment["ONARI_HOTKEY"],
                  !raw.trimmingCharacters(in: .whitespaces).isEmpty
            else { return .default }

            if let parsed = parse(raw) { return parsed }
            FileHandle.standardError.write(
                Data("hotkey: could not parse ONARI_HOTKEY=\"\(raw)\", using \(Combo.default.display)\n".utf8)
            )
            return .default
        }
    }

    /// Fired on key DOWN. The recorder toggles on this — press to start, press
    /// again to stop. Hold-to-speak was worse: with three modifiers it is
    /// uncomfortable, and there is no way to tell whether it is armed.
    public var onPress: (() -> Void)?

    public private(set) var combo: Combo = .default
    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let signature: OSType = 0x4F4E_5249  // 'ONRI'
    private let id: UInt32 = 1

    public init() {}

    deinit { unregister() }

    @discardableResult
    public func register(_ combo: Combo = .fromEnvironment()) -> Bool {
        unregister()
        self.combo = combo

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            HotKey.dispatch(event: event, userData: userData)
        }, 1, &spec, selfPtr, &handler)

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        return status == noErr
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    /// C function pointers cannot capture context, so the instance rides in
    /// `userData` and comes back out here.
    private static func dispatch(
        event: EventRef?, userData: UnsafeMutableRawPointer?
    ) -> OSStatus {
        guard let userData else { return noErr }
        let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()

        if let event {
            var receivedID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &receivedID
            )
            guard receivedID.id == hotKey.id else { return noErr }
        }

        DispatchQueue.main.async { hotKey.onPress?() }
        return noErr
    }
}
