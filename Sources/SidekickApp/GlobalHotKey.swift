import AppKit
import Carbon.HIToolbox
import SidekickCore

enum HotKeyError: LocalizedError, Equatable {
    case invalidBinding
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidBinding:
            return "该组合键不能用作全局快捷键"
        case .registrationFailed(let status):
            return "快捷键注册失败（\(status)），可能已被其他 App 占用"
        }
    }
}

/// Registers a system-wide shortcut through the Carbon Event Manager.
///
/// `RegisterEventHotKey` is used rather than `NSEvent.addGlobalMonitorForEvents`
/// because it needs no Accessibility permission, no usage-description key, and
/// no entitlement — the app can bind a shortcut on first launch with nothing
/// for the user to approve.
@MainActor
final class GlobalHotKeyMonitor {
    /// Four-char code 'SDKC'.
    private static let signature: OSType = 0x53444B43
    private static var installedHandler: EventHandlerRef?

    private let identifier: UInt32
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?

    // No deinit: the monitor lives for the whole process, and a `deinit`
    // cannot touch main-actor state anyway. Rebinding goes through
    // `register(_:)`, which unregisters first.
    init(identifier: UInt32 = 1, handler: @escaping () -> Void) {
        self.identifier = identifier
        self.handler = handler
    }

    /// Replaces any previous registration. Throws when the binding is unusable
    /// or when Carbon refuses it outright.
    ///
    /// Note that success is not proof the shortcut will fire: Carbon returns
    /// `noErr` for chords another app already owns — ⌘Space registers cleanly
    /// and simply never delivers an event — so conflicts cannot be detected
    /// here and have to be discovered by pressing the key.
    func register(_ binding: HotKeyBinding) throws {
        unregister()
        guard binding.isValid else { throw HotKeyError.invalidBinding }
        try Self.installEventHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode),
            Self.carbonModifiers(binding.modifiers),
            EventHotKeyID(signature: Self.signature, id: identifier),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            throw HotKeyError.registrationFailed(status)
        }
        hotKeyRef = reference
        HotKeyRegistry.shared.setHandler(handler, for: identifier)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        HotKeyRegistry.shared.removeHandler(for: identifier)
    }

    private static func installEventHandlerIfNeeded() throws {
        guard installedHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var reference: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventCallback,
            1,
            &spec,
            nil,
            &reference
        )
        guard status == noErr else { throw HotKeyError.registrationFailed(status) }
        installedHandler = reference
    }

    private static func carbonModifiers(_ modifiers: HotKeyModifiers) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }
}

/// Carbon hands the callback a plain C function pointer, which cannot capture
/// context, so handlers are looked up here by hot-key id instead.
@MainActor
private final class HotKeyRegistry {
    static let shared = HotKeyRegistry()

    private var handlers: [UInt32: () -> Void] = [:]

    func setHandler(_ handler: @escaping () -> Void, for identifier: UInt32) {
        handlers[identifier] = handler
    }

    func removeHandler(for identifier: UInt32) {
        handlers[identifier] = nil
    }

    func handle(_ identifier: UInt32) {
        handlers[identifier]?()
    }
}

private let hotKeyEventCallback: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    // Carbon delivers hot-key events on the main run loop.
    MainActor.assumeIsolated { HotKeyRegistry.shared.handle(hotKeyID.id) }
    return noErr
}

extension HotKeyModifiers {
    /// Translates a recorded `NSEvent`'s flags, ignoring caps lock, function,
    /// and the numeric-keypad flag that arrow and keypad keys carry.
    init(eventFlags: NSEvent.ModifierFlags) {
        var modifiers: HotKeyModifiers = []
        if eventFlags.contains(.control) { modifiers.insert(.control) }
        if eventFlags.contains(.option) { modifiers.insert(.option) }
        if eventFlags.contains(.shift) { modifiers.insert(.shift) }
        if eventFlags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}
