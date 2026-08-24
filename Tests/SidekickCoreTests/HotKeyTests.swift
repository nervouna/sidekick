import Foundation
import Testing
@testable import SidekickCore

private func ephemeralDefaults() -> UserDefaults {
    let suite = "hotkey-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test func defaultBindingIsOptionSpace() {
    #expect(HotKeyBinding.default.keyCode == HotKeyCode.space)
    #expect(HotKeyBinding.default.modifiers == [.option])
    #expect(HotKeyBinding.default.displayString == "⌥Space")
}

@Test func displayStringUsesCanonicalModifierOrder() {
    let binding = HotKeyBinding(keyCode: 0x28, modifiers: [.command, .shift, .control, .option])
    #expect(binding.displayString == "⌃⌥⇧⌘K")
}

@Test func displayStringRendersNamedKeys() {
    #expect(HotKeyBinding(keyCode: 0x60, modifiers: []).displayString == "F5")
    #expect(HotKeyBinding(keyCode: 0x7B, modifiers: [.command]).displayString == "⌘←")
    #expect(HotKeyBinding(keyCode: 0x24, modifiers: [.control]).displayString == "⌃↩")
}

@Test func bareOrShiftOnlyChordsAreRejected() {
    #expect(!HotKeyBinding(keyCode: 0x28, modifiers: []).isValid)
    #expect(!HotKeyBinding(keyCode: 0x28, modifiers: [.shift]).isValid)
    #expect(!HotKeyBinding(keyCode: HotKeyCode.space, modifiers: []).isValid)
}

@Test func qualifyingModifiersMakeAChordValid() {
    #expect(HotKeyBinding.default.isValid)
    #expect(HotKeyBinding(keyCode: 0x28, modifiers: [.control, .option]).isValid)
    #expect(HotKeyBinding(keyCode: 0x28, modifiers: [.command, .shift]).isValid)
}

@Test func functionKeysMayStandAlone() {
    #expect(HotKeyBinding(keyCode: 0x7A, modifiers: []).isValid)
    #expect(HotKeyBinding(keyCode: 0x5A, modifiers: []).isValid)
    #expect(HotKeyCode.isFunctionKey(0x60))
    #expect(!HotKeyCode.isFunctionKey(HotKeyCode.space))
}

@Test func unknownAndModifierOnlyKeyCodesAreRejected() {
    #expect(!HotKeyBinding(keyCode: 0x37, modifiers: [.command]).isValid)
    #expect(!HotKeyBinding(keyCode: 0xFF, modifiers: [.command]).isValid)
    #expect(HotKeyCode.name(for: 0x37) == nil)
}

@Test func bindingSurvivesCodableRoundTrip() throws {
    let binding = HotKeyBinding(keyCode: 0x28, modifiers: [.control, .option])
    let data = try JSONEncoder().encode(binding)
    #expect(try JSONDecoder().decode(HotKeyBinding.self, from: data) == binding)
}

@Test func storeRoundTripsSavedBinding() {
    let store = UserDefaultsHotKeyStore(defaults: ephemeralDefaults())
    let binding = HotKeyBinding(keyCode: 0x28, modifiers: [.control, .option])
    store.save(binding)
    #expect(store.load() == binding)
}

@Test func storeFallsBackToDefaultWhenEmpty() {
    let store = UserDefaultsHotKeyStore(defaults: ephemeralDefaults())
    #expect(store.load() == .default)
}

@Test func storeFallsBackToDefaultOnCorruptOrInvalidPayload() {
    let corruptDefaults = ephemeralDefaults()
    corruptDefaults.set(Data("not json".utf8), forKey: UserDefaultsHotKeyStore.defaultsKey)
    #expect(UserDefaultsHotKeyStore(defaults: corruptDefaults).load() == .default)

    let invalidDefaults = ephemeralDefaults()
    let unusable = HotKeyBinding(keyCode: 0x28, modifiers: [.shift])
    invalidDefaults.set(try! JSONEncoder().encode(unusable), forKey: UserDefaultsHotKeyStore.defaultsKey)
    #expect(UserDefaultsHotKeyStore(defaults: invalidDefaults).load() == .default)
}
