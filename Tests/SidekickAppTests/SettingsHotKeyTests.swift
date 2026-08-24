import Foundation
import Testing
@testable import SidekickApp
import SidekickCore

private struct NoSecrets: SecretStoring {
    func read(account: String) throws -> String? { nil }
    func save(_ value: String, account: String) throws {}
    func delete(account: String) throws {}
}

private struct NoEnvironment: EnvironmentReading {
    func value(for name: String) -> String? { nil }
}

private final class RecordingHotKeyStore: HotKeyStoring, @unchecked Sendable {
    private(set) var saved: [HotKeyBinding] = []
    var stored: HotKeyBinding = .default
    func load() -> HotKeyBinding { stored }
    func save(_ binding: HotKeyBinding) {
        stored = binding
        saved.append(binding)
    }
}

private struct RebindFailure: Error {}

@MainActor
private func makeViewModel(
    store: RecordingHotKeyStore = RecordingHotKeyStore(),
    rebind: @escaping (HotKeyBinding) throws -> Void = { _ in }
) -> (SettingsViewModel, RecordingHotKeyStore) {
    let viewModel = SettingsViewModel(
        keyProvider: KeyProvider(secrets: NoSecrets(), environment: NoEnvironment()),
        hotKeyStore: store,
        initialHotKeyStatus: "",
        onRebindHotKey: rebind
    )
    return (viewModel, store)
}

@Test @MainActor
func applyingAValidChordRegistersAndPersistsIt() {
    var registered: [HotKeyBinding] = []
    let (viewModel, store) = makeViewModel(rebind: { registered.append($0) })
    let chord = HotKeyBinding(keyCode: 0x28, modifiers: [.control, .option])

    viewModel.applyHotKey(chord)

    #expect(registered == [chord])
    #expect(store.saved == [chord])
    #expect(viewModel.hotKey == chord)
}

@Test @MainActor
func anInvalidChordIsRejectedWithoutTouchingTheRegistration() {
    var registered: [HotKeyBinding] = []
    let (viewModel, store) = makeViewModel(rebind: { registered.append($0) })

    viewModel.applyHotKey(HotKeyBinding(keyCode: 0x28, modifiers: [.shift]))

    #expect(registered.isEmpty)
    #expect(store.saved.isEmpty)
    #expect(viewModel.hotKey == .default)
    #expect(!viewModel.hotKeyStatus.isEmpty)
}

@Test @MainActor
func aRefusedChordRestoresThePreviousBinding() {
    var attempts: [HotKeyBinding] = []
    let rejected = HotKeyBinding(keyCode: 0x28, modifiers: [.control, .option])
    let (viewModel, store) = makeViewModel(rebind: { binding in
        attempts.append(binding)
        if binding == rejected { throw RebindFailure() }
    })

    viewModel.applyHotKey(rejected)

    // Registering tears the old chord down first, so the previous binding has
    // to be put back or the user is left with no shortcut at all.
    #expect(attempts == [rejected, .default])
    #expect(store.saved.isEmpty)
    #expect(viewModel.hotKey == .default)
}

@Test @MainActor
func reapplyingTheCurrentChordIsANoOp() {
    var registered: [HotKeyBinding] = []
    let (viewModel, store) = makeViewModel(rebind: { registered.append($0) })

    viewModel.applyHotKey(.default)

    #expect(registered.isEmpty)
    #expect(store.saved.isEmpty)
}
