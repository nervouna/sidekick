import Foundation
import Testing
@testable import SidekickApp
import SidekickCore

private struct EmptySecrets: SecretStoring {
    func read(account: String) throws -> String? { nil }
    func save(_ value: String, account: String) throws {}
    func delete(account: String) throws {}
}

private struct FixedEnvironment: EnvironmentReading {
    func value(for name: String) -> String? { "test-key" }
}

private final class FakePasteboard: PasteboardReading, @unchecked Sendable {
    var text: String?
    func string() -> String? { text }
}

private struct DeepSeekOnlyEnvironment: EnvironmentReading {
    func value(for name: String) -> String? {
        name == APIService.deepSeek.environmentName ? "test-key" : nil
    }
}

private struct ImmediateDeepSeek: DeepSeekStreaming {
    func stream(request: ModelRequest, apiKey: String) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.contentDelta("answer"))
            continuation.yield(.usage(TokenUsage(totalTokens: 1_520)))
            continuation.yield(.finished(.stop))
            continuation.finish()
        }
    }
}

private struct NeverUsedTavily: TavilySearching {
    func search(query: String, apiKey: String) async throws -> [TavilyResult] { [] }
}

private final class FailingSaveStore: SessionStoring, @unchecked Sendable {
    let initial: ChatSession
    init(initial: ChatSession = ChatSession()) { self.initial = initial }
    func load(now: Date) throws -> ChatSession { initial }
    func save(_ session: ChatSession) throws { throw CocoaError(.fileWriteUnknown) }
    func delete() throws {}
}

private final class FailAfterFirstSaveStore: SessionStoring, @unchecked Sendable {
    private(set) var saved = ChatSession()
    private var saveCount = 0
    func load(now: Date) throws -> ChatSession { ChatSession(createdAt: now) }
    func save(_ session: ChatSession) throws {
        saveCount += 1
        if saveCount > 1 { throw CocoaError(.fileWriteUnknown) }
        saved = session
    }
    func delete() throws {}
}

private final class MutableDateProvider: DateProviding, @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
    func now() -> Date { date }
}

@MainActor
private func contextViewModel(
    store: (any SessionStoring)? = nil,
    pasteboard: (any PasteboardReading)? = nil
) -> ChatViewModel {
    let resolvedStore: any SessionStoring = store ?? SessionStore(
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("session.json")
    )
    return ChatViewModel(
        sessionStore: resolvedStore,
        keyProvider: KeyProvider(secrets: EmptySecrets(), environment: FixedEnvironment()),
        agent: AgentRunner(deepSeek: ImmediateDeepSeek(), tavily: NeverUsedTavily()),
        pasteboard: pasteboard ?? FakePasteboard()
    )
}

@Test func attachedContextClampTruncatesAtFourThousandCharacters() {
    #expect(AttachedContext.clamp("   ").text.isEmpty)
    let exact = String(repeating: "a", count: ContextPolicy.attachedContextCharacterLimit)
    #expect(AttachedContext.clamp(exact) == (exact, false))
    let oversized = exact + "z"
    let clamped = AttachedContext.clamp(oversized)
    #expect(clamped.truncated)
    #expect(clamped.text.hasPrefix(exact))
    #expect(clamped.text.hasSuffix("[已截断]"))
    #expect(!clamped.text.contains("z"))
}

@Test @MainActor
func clipboardAttachSendAndRetryKeepStructuredContext() async throws {
    let pasteboard = FakePasteboard()
    pasteboard.text = "  clipboard body  "
    let viewModel = contextViewModel(pasteboard: pasteboard)
    viewModel.attachClipboardContext()
    #expect(viewModel.attachedContext == "clipboard body")

    viewModel.input = String(repeating: "q", count: 1_000)
    #expect(viewModel.canSend)
    viewModel.send()
    while viewModel.isGenerating { await Task.yield() }

    #expect(viewModel.attachedContext == nil)
    #expect(viewModel.session.messages.first?.content == String(repeating: "q", count: 1_000))
    #expect(viewModel.session.messages.first?.attachedContext == "clipboard body")
    #expect(viewModel.conversationItems.contains { item in
        if case .message(_, let message) = item {
            return message.attachedContext == "clipboard body" && message.content == String(repeating: "q", count: 1_000)
        }
        return false
    })

    let userID = viewModel.session.messages.first?.id
    let replyID = viewModel.session.messages.last?.id
    viewModel.regenerate(replyID: try #require(replyID))
    while viewModel.isGenerating { await Task.yield() }
    #expect(viewModel.session.messages.first?.id == userID)
    #expect(viewModel.session.messages.first?.attachedContext == "clipboard body")
}

@Test @MainActor
func clipboardChipClearsOnDismissAndNewConversation() {
    let pasteboard = FakePasteboard()
    pasteboard.text = "keep"
    let viewModel = contextViewModel(pasteboard: pasteboard)
    viewModel.attachClipboardContext()
    viewModel.clearAttachedContext()
    #expect(viewModel.attachedContext == nil)

    pasteboard.text = "again"
    viewModel.attachClipboardContext()
    viewModel.newConversation()
    #expect(viewModel.attachedContext == nil)
}

@Test @MainActor
func emptyPasteboardDoesNotAttach() {
    let viewModel = contextViewModel()
    viewModel.attachClipboardContext()
    #expect(viewModel.attachedContext == nil)
}

@Test @MainActor
func sendSucceedsWithOnlyADeepSeekKey() async {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("session.json")
    let viewModel = ChatViewModel(
        sessionStore: SessionStore(fileURL: fileURL),
        keyProvider: KeyProvider(secrets: EmptySecrets(), environment: DeepSeekOnlyEnvironment()),
        agent: AgentRunner(deepSeek: ImmediateDeepSeek(), tavily: NeverUsedTavily())
    )
    viewModel.input = "hello"
    viewModel.send()
    while viewModel.isGenerating { await Task.yield() }

    #expect(viewModel.session.messages.contains { $0.role == .user && $0.content == "hello" })
    #expect(viewModel.session.messages.last?.content == "answer")
    #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func composerCountsCharactersWithoutTruncatingPastes() {
    let viewModel = contextViewModel()
    viewModel.input = String(repeating: "a", count: 799)
    #expect(!viewModel.showsInputCharacterCount)
    #expect(viewModel.canSend)

    viewModel.input.append("a")
    #expect(viewModel.inputCharacterCount == 800)
    #expect(viewModel.showsInputCharacterCount)
    #expect(!viewModel.isInputOverLimit)

    viewModel.input = String(repeating: "🙂", count: 1_000)
    #expect(viewModel.inputCharacterCount == 1_000)
    #expect(viewModel.canSend)

    viewModel.input.append("🙂")
    #expect(viewModel.inputCharacterCount == 1_001)
    #expect(viewModel.input.count == 1_001)
    #expect(viewModel.isInputOverLimit)
    #expect(!viewModel.canSend)
    viewModel.send()
    #expect(viewModel.session.messages.isEmpty)
    #expect(viewModel.input.count == 1_001)
    #expect(viewModel.errorMessage == "问题不能超过 1000 个字符")
}

@Test @MainActor
func initialSaveFailureKeepsInputAndOriginalSessionAndDoesNotStartGeneration() {
    let existing = ChatMessage(role: .user, content: "existing")
    let initial = ChatSession(messages: [existing])
    let viewModel = contextViewModel(store: FailingSaveStore(initial: initial))
    viewModel.input = "new question"
    viewModel.send()

    #expect(viewModel.input == "new question")
    #expect(viewModel.session == initial)
    #expect(!viewModel.isGenerating)
    #expect(viewModel.errorMessage != nil)
}

@Test @MainActor
func budgetTrimmingRemovesOldMessagesAndShowsOnlyOneTransientNotice() {
    let viewModel = contextViewModel()
    let oldUser = ChatMessage(role: .user, content: String(repeating: "x", count: 9_000))
    let oldAnswer = ChatMessage(role: .assistant, content: String(repeating: "y", count: 9_000))
    viewModel.session = ChatSession(messages: [oldUser, oldAnswer])
    viewModel.input = "new"
    viewModel.send()

    #expect(!viewModel.session.messages.contains(where: { $0.id == oldUser.id || $0.id == oldAnswer.id }))
    #expect(viewModel.showsContextTrimNotice)
    #expect(viewModel.conversationItems.filter { $0 == .contextNotice }.count == 1)
}

@Test @MainActor
func retryRemovesPartialArtifactWithoutDuplicatingUserMessage() {
    let viewModel = contextViewModel()
    let user = ChatMessage(role: .user, content: "question")
    let partial = ChatMessage(role: .assistant, content: "partial", completionState: .interrupted)
    viewModel.session = ChatSession(messages: [user, partial])
    viewModel.retry()

    #expect(viewModel.session.messages.filter { $0.role == .user }.map(\.id) == [user.id])
    #expect(!viewModel.session.messages.contains(where: { $0.id == partial.id }))
}

@Test @MainActor
func finalSaveFailureKeepsGeneratedAnswerInMemoryAndShowsNonFatalError() async {
    let store = FailAfterFirstSaveStore()
    let viewModel = contextViewModel(store: store)
    viewModel.input = "question"
    viewModel.send()
    while viewModel.isGenerating { await Task.yield() }

    #expect(viewModel.session.messages.last?.content == "answer")
    #expect(viewModel.session.messages.last?.completionState == .complete)
    #expect(viewModel.session.messages.last?.tokenCount == 1_520)
    #expect(viewModel.session.messages.last?.responseEndedAt != nil)
    #expect(viewModel.errorMessage == "回答已生成，但无法保存本次会话")
}

@Test @MainActor
func regenerateHistoricalReplyDiscardsDependentTurnsAndKeepsTheOriginalQuestion() async {
    let viewModel = contextViewModel()
    let firstUser = ChatMessage(role: .user, content: "first")
    let firstReply = ChatMessage(role: .assistant, content: "old first answer", completionState: .complete)
    let secondUser = ChatMessage(role: .user, content: "follow-up")
    let secondReply = ChatMessage(role: .assistant, content: "old follow-up answer", completionState: .complete)
    viewModel.session = ChatSession(messages: [firstUser, firstReply, secondUser, secondReply])

    viewModel.regenerate(replyID: firstReply.id)
    while viewModel.isGenerating { await Task.yield() }

    #expect(viewModel.session.messages.first?.id == firstUser.id)
    #expect(viewModel.session.messages.filter { $0.role == .user }.map(\.content) == ["first"])
    #expect(!viewModel.session.messages.contains { $0.id == firstReply.id || $0.id == secondUser.id || $0.id == secondReply.id })
    #expect(viewModel.session.messages.last?.content == "answer")
    #expect(viewModel.session.messages.last?.tokenCount == 1_520)
}

@Test @MainActor
func popoverRefreshExpiresSessionAtThirtyMinutesAndDeletesFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let fileURL = directory.appendingPathComponent("session.json")
    let store = SessionStore(fileURL: fileURL)
    let start = Date(timeIntervalSince1970: 20_000)
    var session = ChatSession(createdAt: start)
    session.append(ChatMessage(role: .user, content: "temporary"), now: start)
    try store.save(session)
    let clock = MutableDateProvider(start.addingTimeInterval(1_799))
    let viewModel = ChatViewModel(sessionStore: store, dateProvider: clock)
    viewModel.refreshForPresentation()
    #expect(viewModel.session.messages.count == 1)

    clock.date = start.addingTimeInterval(1_800)
    viewModel.refreshForPresentation()
    #expect(viewModel.session.messages.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
}

@Test @MainActor
func popoverRefreshRebuildsMarkdownWithoutChangingTheConversation() {
    let message = ChatMessage(role: .assistant, content: "[Link](https://example.com)")
    let viewModel = contextViewModel()
    viewModel.session = ChatSession(messages: [message])
    let originalItems = viewModel.conversationItems

    viewModel.refreshForPresentation()

    #expect(viewModel.markdownRenderGeneration == 1)
    #expect(viewModel.conversationItems == originalItems)
}
