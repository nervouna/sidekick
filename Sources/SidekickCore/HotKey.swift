import Foundation

/// Modifier flags for a global shortcut.
///
/// Deliberately independent of Carbon's `cmdKey`/`optionKey` bitmask and of
/// AppKit's `NSEvent.ModifierFlags` so that this module stays Foundation-only.
/// The app layer translates in both directions.
public struct HotKeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = HotKeyModifiers(rawValue: 1 << 0)
    public static let option = HotKeyModifiers(rawValue: 1 << 1)
    public static let shift = HotKeyModifiers(rawValue: 1 << 2)
    public static let command = HotKeyModifiers(rawValue: 1 << 3)

    /// Modifiers strong enough to carry a shortcut on their own. `shift` is
    /// absent on purpose: a shift-only chord would swallow ordinary typing
    /// system-wide.
    public static let qualifying: HotKeyModifiers = [.control, .option, .command]

    /// Apple's canonical display order.
    public var displayString: String {
        var glyphs = ""
        if contains(.control) { glyphs += "⌃" }
        if contains(.option) { glyphs += "⌥" }
        if contains(.shift) { glyphs += "⇧" }
        if contains(.command) { glyphs += "⌘" }
        return glyphs
    }
}

/// A key the user presses together with `HotKeyModifiers` to summon Sidekick.
///
/// `keyCode` is a macOS virtual key code (`kVK_*`), which is layout-independent
/// at the hardware level; only the human-readable name is resolved through a
/// fixed US-QWERTY table.
public struct HotKeyBinding: Equatable, Codable, Hashable, Sendable {
    public let keyCode: UInt16
    public let modifiers: HotKeyModifiers

    public init(keyCode: UInt16, modifiers: HotKeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let `default` = HotKeyBinding(keyCode: HotKeyCode.space, modifiers: [.option])

    /// Function keys may stand alone; everything else needs a qualifying modifier.
    public var isValid: Bool {
        guard HotKeyCode.name(for: keyCode) != nil else { return false }
        if HotKeyCode.isFunctionKey(keyCode) { return true }
        return !modifiers.isDisjoint(with: .qualifying)
    }

    /// Menu-style rendering, e.g. `⌥Space` or `⌃⇧⌘K`.
    public var displayString: String {
        modifiers.displayString + (HotKeyCode.name(for: keyCode) ?? "…")
    }
}

/// Virtual key codes and their display names.
public enum HotKeyCode {
    public static let space: UInt16 = 0x31
    public static let escape: UInt16 = 0x35
    public static let delete: UInt16 = 0x33

    private static let functionKeys: Set<UInt16> = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A
    ]

    public static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        functionKeys.contains(keyCode)
    }

    /// Display name for a virtual key code, or `nil` when the code is unknown
    /// or is a modifier key that cannot anchor a shortcut on its own.
    public static func name(for keyCode: UInt16) -> String? { names[keyCode] }

    private static let names: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
        0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
        0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x1F: "O",
        0x20: "U", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x28: "K",
        0x2D: "N", 0x2E: "M",

        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6",
        0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0",

        0x18: "=", 0x1B: "-", 0x1E: "]", 0x21: "[", 0x27: "'", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2F: ".", 0x32: "`",

        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋",
        0x4C: "⌤", 0x72: "Help", 0x75: "⌦",

        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",

        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5",
        0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10",
        0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
        0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20"
    ]
}

public protocol HotKeyStoring: Sendable {
    func load() -> HotKeyBinding
    func save(_ binding: HotKeyBinding)
}

/// Persists the binding in `UserDefaults`. Unlike API keys this is a
/// preference, not a secret, so it does not belong in the keychain.
public final class UserDefaultsHotKeyStore: HotKeyStoring, @unchecked Sendable {
    public static let defaultsKey = "io.damao.sidekick.hotkey"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Falls back to the default binding when nothing is stored, when the
    /// payload is corrupt, or when it decodes to something unusable.
    public func load() -> HotKeyBinding {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let binding = try? decoder.decode(HotKeyBinding.self, from: data),
              binding.isValid
        else { return .default }
        return binding
    }

    public func save(_ binding: HotKeyBinding) {
        guard let data = try? encoder.encode(binding) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
