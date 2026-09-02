import Foundation
import Testing
@testable import SidekickCore

@Test func estimatorLocksTextFormulaOverheadsAndCorrectionRules() {
    #expect(ContextEstimator.rawTextTokens("abc") == 3)
    #expect(ContextEstimator.rawTextTokens("中文") == 4)
    #expect(ContextEstimator.rawTextTokens("https://example.com/a?b=c") > 0)

    let call = ToolCall(
        id: "call-1",
        function: ToolFunction(name: "web_search", arguments: #"{"query":"🙂"}"#)
    )
    let message = ChatMessage(
        role: .assistant,
        content: "answer",
        reasoningContent: "reasoning",
        toolCalls: [call]
    )
    let estimator = ContextEstimator()
    let textTotal = ["answer", "reasoning", "call-1", "function", "web_search", #"{"query":"🙂"}"#]
        .reduce(0) { $0 + ContextEstimator.rawTextTokens($1) }
    #expect(estimator.messageTokens(message) == ContextPolicy.messageOverheadTokens
        + ContextPolicy.toolCallOverheadTokens + textTotal)

    let withAttachment = ChatMessage(role: .user, content: "q", attachedContext: "clip")
    #expect(estimator.messageTokens(withAttachment) == ContextPolicy.messageOverheadTokens
        + ContextEstimator.rawTextTokens("q") + ContextEstimator.rawTextTokens("clip"))

    var corrected = ContextEstimator()
    corrected.observe(actualPromptTokens: 110, estimatedPromptTokens: 100)
    #expect(abs(corrected.correctionFactor - 1.21) < 0.0001)
    corrected.observe(actualPromptTokens: 100, estimatedPromptTokens: 110)
    #expect(abs(corrected.correctionFactor - 1.21) < 0.0001)
    corrected.observe(actualPromptTokens: 10_000, estimatedPromptTokens: 100)
    #expect(corrected.correctionFactor == ContextPolicy.maximumCorrectionFactor)
}

@Test func contextManagerUsesExactBoundaryAndEvictsOldestWholeTurn() throws {
    let oldUser = ChatMessage(role: .user, content: String(repeating: "old", count: 80))
    let oldAnswer = ChatMessage(role: .assistant, content: String(repeating: "answer", count: 80))
    let newUser = ChatMessage(role: .user, content: "new")
    let messages = [oldUser, oldAnswer, newUser]
    let estimator = ContextEstimator()
    let exact = estimator.promptTokens(systemPrompt: "system", messages: messages)
    let manager = ContextManager()

    let boundary = try manager.prepare(
        systemPrompt: "system",
        messages: messages,
        estimator: estimator,
        inputTarget: exact
    )
    #expect(boundary.conversationMessages.map(\.id) == messages.map(\.id))

    let trimmed = try manager.prepare(
        systemPrompt: "system",
        messages: messages,
        estimator: estimator,
        inputTarget: exact - 1
    )
    #expect(trimmed.conversationMessages == [newUser])
    #expect(trimmed.evictedMessageIDs == Set([oldUser.id, oldAnswer.id]))
}

@Test func contextManagerPreservesToolProtocolAndNormalizesReasoning() throws {
    let directUser = ChatMessage(role: .user, content: "stable")
    let directAnswer = ChatMessage(
        role: .assistant,
        content: "answer",
        reasoningContent: "must be removed"
    )
    let searchUser = ChatMessage(role: .user, content: "latest")
    let call = ToolCall(
        id: "call",
        function: ToolFunction(name: "web_search", arguments: #"{"query":"latest"}"#)
    )
    let toolAssistant = ChatMessage(
        role: .assistant,
        reasoningContent: "must be retained",
        toolCalls: [call]
    )
    let tool = ChatMessage(role: .tool, content: "[]", toolCallID: "call")
    let final = ChatMessage(role: .assistant, content: "result", reasoningContent: "remove final")
    let current = ChatMessage(role: .user, content: "next")
    let prepared = try ContextManager().prepare(
        systemPrompt: "system",
        messages: [
            ChatMessage(role: .system, content: "injected"),
            directUser, directAnswer, searchUser, toolAssistant, tool, final, current
        ],
        estimator: ContextEstimator(),
        inputTarget: 20_000
    )

    #expect(prepared.conversationMessages.allSatisfy { $0.role != .system })
    #expect(prepared.conversationMessages.first(where: { $0.id == directAnswer.id })?.reasoningContent == nil)
    #expect(prepared.conversationMessages.first(where: { $0.id == toolAssistant.id })?.reasoningContent == "must be retained")
    #expect(prepared.conversationMessages.first(where: { $0.id == final.id })?.reasoningContent == nil)
    #expect(prepared.conversationMessages.contains(where: { $0.id == toolAssistant.id }))
    #expect(prepared.conversationMessages.contains(where: { $0.id == tool.id }))
}

@Test func incompleteTurnsRemainNonReturnableAndCurrentUserAlwaysSurvives() throws {
    for state in [
        AssistantCompletionState.cancelled,
        .truncated,
        .filtered,
        .interrupted
    ] {
        let oldUser = ChatMessage(role: .user, content: "old")
        let partial = ChatMessage(role: .assistant, content: "partial", completionState: state)
        let current = ChatMessage(role: .user, content: "current")
        let prepared = try ContextManager().prepare(
            systemPrompt: "system",
            messages: [oldUser, partial, current],
            estimator: ContextEstimator(),
            inputTarget: 10_000
        )
        #expect(prepared.conversationMessages == [current])
        #expect(prepared.evictedMessageIDs.isEmpty)
    }
}

@Test func attachedContextThatCannotFitInputTargetFailsWithoutMutatingMessages() {
    let user = ChatMessage(
        role: .user,
        content: "q",
        attachedContext: String(repeating: "中", count: ContextPolicy.attachedContextCharacterLimit)
    )
    let messages = [user]
    let estimator = ContextEstimator()
    let exact = estimator.promptTokens(systemPrompt: "s", messages: messages)
    #expect(throws: SidekickError.contextBudgetExceeded) {
        try ContextManager().prepare(
            systemPrompt: "s",
            messages: messages,
            estimator: estimator,
            inputTarget: exact - 1
        )
    }
    #expect(messages == [user])
}

@Test func oversizedCurrentTurnFailsWithoutMutatingInput() {
    let messages = [ChatMessage(role: .user, content: String(repeating: "x", count: 20_000))]
    let original = messages
    #expect(throws: SidekickError.contextBudgetExceeded) {
        try ContextManager().prepare(
            systemPrompt: "system",
            messages: messages,
            estimator: ContextEstimator()
        )
    }
    #expect(messages == original)
}

@Test func toolFollowUpCanReduceGenerationBudgetForAnOversizedCurrentTurn() throws {
    let current = ChatMessage(role: .user, content: String(repeating: "x", count: 14_000))
    let prepared = try ContextManager().prepareToolFollowUp(
        systemPrompt: "system",
        messages: [current],
        estimator: ContextEstimator()
    )
    let request = try prepared.request(isToolFollowUp: true)
    #expect(request.options.maxTokens < ContextPolicy.preferredGenerationTokens)
    #expect(request.options.maxTokens >= ContextPolicy.minimumFinalGenerationTokens)
    #expect(request.options.maxTokens + prepared.estimatedPromptTokens <= ContextPolicy.totalTokenBudget)
}

@Test func toolFollowUpRefusesToCrossTheMinimumFinalAnswerReserve() {
    let prepared = PreparedConversation(
        systemPrompt: "system",
        conversationMessages: [],
        estimatedPromptTokens: ContextPolicy.totalTokenBudget
            - ContextPolicy.minimumFinalGenerationTokens + 1
    )
    #expect(throws: SidekickError.contextBudgetExceeded) {
        try prepared.request(isToolFollowUp: true)
    }
}
