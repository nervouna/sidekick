import Foundation
import Testing
@testable import SidekickApp
import SidekickCore

@MainActor
private func makeViewModel() -> ChatViewModel {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("session.json")
    return ChatViewModel(sessionStore: SessionStore(fileURL: fileURL))
}

@MainActor
@Test func composerFocusRequestStartsAtZero() {
    #expect(makeViewModel().composerFocusRequest == 0)
}

@MainActor
@Test func eachFocusRequestAdvancesTheCounter() {
    let viewModel = makeViewModel()
    viewModel.requestComposerFocus()
    #expect(viewModel.composerFocusRequest == 1)
    // Repeat summons must still register, which is why this is a counter
    // rather than a flag.
    viewModel.requestComposerFocus()
    #expect(viewModel.composerFocusRequest == 2)
}
