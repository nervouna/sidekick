import Foundation
import Testing
@testable import SidekickApp
import SidekickCore

private enum ItemKind: Equatable {
    case user(String)
    case assistant(String)
    case thinking(Bool)
    case search(Bool)
    case activitySummary(String, Bool)
    case streaming(String)
    case contextNotice
}

private extension ConversationItem {
    var testKind: ItemKind {
        switch self {
        case .message(_, let message):
            if message.role == .user { return .user(message.content ?? "") }
            return .assistant(message.content ?? "")
        case .activity(let activity):
            return activity.kind == .thinking
                ? .thinking(activity.completed)
                : .search(activity.completed)
        case .activitySummary(let summary):
            return .activitySummary(summary.label, summary.completed)
        case .streaming(_, let content):
            return .streaming(content)
        case .contextNotice:
            return .contextNotice
        }
    }
}

@MainActor
private func makeViewModel(messages: [ChatMessage]) -> ChatViewModel {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("session.json")
    let viewModel = ChatViewModel(sessionStore: SessionStore(fileURL: fileURL))
    viewModel.session = ChatSession(messages: messages)
    return viewModel
}

@Test @MainActor
func directReplyKeepsItsTimelinePositionWhenCommitted() {
    let user = ChatMessage(role: .user, content: "Question")
    let final = ChatMessage(role: .assistant, content: "**Answer**", reasoningContent: "hidden")
    let viewModel = makeViewModel(messages: [user])

    viewModel.beginActiveTimeline()
    viewModel.handle(.thinkingStarted)
    viewModel.handle(.contentDelta("**Ans"))

    #expect(viewModel.conversationItems.map(\.testKind) == [
        .user("Question"), .thinking(false), .streaming("**Ans")
    ])
    let streamingID = viewModel.conversationItems.last?.id

    viewModel.handle(.thinkingCompleted)
    viewModel.handle(.finished([user, final]))

    #expect(viewModel.conversationItems.map(\.testKind) == [
        .user("Question"), .thinking(true), .assistant("**Answer**")
    ])
    #expect(viewModel.conversationItems.last?.id == streamingID)
}

@Test @MainActor
func completedReplyStoresUsageAcrossEveryModelCall() {
    let user = ChatMessage(role: .user, content: "Question")
    let final = ChatMessage(role: .assistant, content: "Answer", completionState: .complete)
    let viewModel = makeViewModel(messages: [user])

    viewModel.beginActiveTimeline()
    viewModel.handle(.usage(TokenUsage(totalTokens: 800), estimatedPromptTokens: 700))
    viewModel.handle(.usage(TokenUsage(totalTokens: 720), estimatedPromptTokens: 600))
    viewModel.handle(.finished([user, final]))

    #expect(viewModel.session.messages.last?.tokenCount == 1_520)
    #expect(viewModel.session.messages.last?.responseEndedAt != nil)
}

@Test @MainActor
func searchActivitiesRemainBeforeTheFinalReply() {
    let user = ChatMessage(role: .user, content: "Latest?")
    let toolCall = ToolCall(id: "call", function: ToolFunction(name: "web_search", arguments: "{}"))
    let internalAssistant = ChatMessage(
        role: .assistant,
        content: "internal",
        reasoningContent: "hidden",
        toolCalls: [toolCall]
    )
    let tool = ChatMessage(role: .tool, content: "result", toolCallID: "call")
    let final = ChatMessage(role: .assistant, content: "Final")
    let viewModel = makeViewModel(messages: [user])

    viewModel.beginActiveTimeline()
    viewModel.handle(.thinkingStarted)
    viewModel.handle(.thinkingCompleted)
    viewModel.handle(.toolCallStarted)
    viewModel.handle(.toolCallCompleted)
    viewModel.handle(.thinkingStarted)
    viewModel.handle(.thinkingCompleted)
    viewModel.handle(.contentDelta("Final"))
    viewModel.handle(.finished([user, internalAssistant, tool, final]))

    #expect(viewModel.conversationItems.map(\.testKind) == [
        .user("Latest?"),
        .activitySummary("已思考 2 次 · 已搜索 1 次", true),
        .assistant("Final")
    ])
}

@Test @MainActor
func thirdActivityReplacesTheWholeActivityGroupWithOneStableSummary() {
    let user = ChatMessage(role: .user, content: "Latest?")
    let viewModel = makeViewModel(messages: [user])

    viewModel.beginActiveTimeline()
    viewModel.handle(.thinkingStarted)
    viewModel.handle(.thinkingCompleted)
    viewModel.handle(.toolCallStarted)

    #expect(viewModel.conversationItems.map(\.testKind) == [
        .user("Latest?"), .thinking(true), .search(false)
    ])

    viewModel.handle(.toolCallCompleted)
    viewModel.handle(.thinkingStarted)

    #expect(viewModel.conversationItems.map(\.testKind) == [
        .user("Latest?"),
        .activitySummary("已思考 1 次 · 已搜索 1 次 · 正在思考…", false)
    ])
    let summaryID = viewModel.conversationItems.last?.id

    viewModel.handle(.thinkingCompleted)
    viewModel.handle(.toolCallStarted)

    #expect(viewModel.conversationItems.map(\.testKind) == [
        .user("Latest?"),
        .activitySummary("已思考 2 次 · 已搜索 1 次 · 正在搜索网页…", false)
    ])
    #expect(viewModel.conversationItems.last?.id == summaryID)

    viewModel.handle(.toolCallCompleted)
    #expect(viewModel.conversationItems.map(\.testKind) == [
        .user("Latest?"),
        .activitySummary("已思考 2 次 · 已搜索 2 次", true)
    ])
    #expect(viewModel.conversationItems.last?.id == summaryID)
}

@Test @MainActor
func priorRepliesStayBeforeTheCurrentTurn() {
    let oldUser = ChatMessage(role: .user, content: "Old question")
    let oldReply = ChatMessage(role: .assistant, content: "Old answer")
    let newUser = ChatMessage(role: .user, content: "New question")
    let viewModel = makeViewModel(messages: [oldUser, oldReply, newUser])

    viewModel.beginActiveTimeline()
    viewModel.handle(.thinkingStarted)

    #expect(viewModel.conversationItems.map(\.testKind) == [
        .user("Old question"),
        .assistant("Old answer"),
        .user("New question"),
        .thinking(false)
    ])
}

@Test @MainActor
func cancelledPartialReplyIsCommittedBelowActivities() {
    let user = ChatMessage(role: .user, content: "Question")
    let viewModel = makeViewModel(messages: [user])

    viewModel.beginActiveTimeline()
    viewModel.handle(.thinkingStarted)
    viewModel.handle(.contentDelta("Partial"))
    viewModel.cancelGeneration()

    #expect(viewModel.conversationItems.map(\.testKind) == [
        .user("Question"), .thinking(false), .assistant("Partial")
    ])
    #expect(viewModel.session.messages.last?.content == "Partial")
    #expect(viewModel.session.messages.last?.completionState == .cancelled)
}

@Test @MainActor
func internalMessagesNeverEnterTheVisibleTimeline() {
    let call = ToolCall(id: "call", function: ToolFunction(name: "web_search", arguments: "{}"))
    let messages = [
        ChatMessage(role: .system, content: "system"),
        ChatMessage(role: .user, content: "visible user"),
        ChatMessage(role: .assistant, reasoningContent: "reasoning only"),
        ChatMessage(role: .assistant, content: "tool request", toolCalls: [call]),
        ChatMessage(role: .tool, content: "tool result"),
        ChatMessage(role: .assistant, content: "visible assistant")
    ]
    let viewModel = makeViewModel(messages: messages)

    #expect(viewModel.conversationItems.map(\.testKind) == [
        .user("visible user"), .assistant("visible assistant")
    ])
}

@Test @MainActor
func startingAnotherTurnAndCreatingANewConversationResetTransientState() {
    let user = ChatMessage(role: .user, content: "Question")
    let viewModel = makeViewModel(messages: [user])
    viewModel.beginActiveTimeline()
    viewModel.handle(.thinkingStarted)
    viewModel.handle(.contentDelta("Old partial"))

    viewModel.session.append(ChatMessage(role: .user, content: "Next"))
    viewModel.beginActiveTimeline()

    #expect(viewModel.activities.isEmpty)
    #expect(viewModel.streamingContent.isEmpty)
    #expect(viewModel.activeInsertionPoint == 2)

    viewModel.newConversation()
    #expect(viewModel.conversationItems.isEmpty)
    #expect(viewModel.activeInsertionPoint == nil)
}

@Test @MainActor
func popoverHeightTracksMeasuredContentAndResetsForANewConversation() {
    let viewModel = makeViewModel(messages: [])

    viewModel.updateLayoutHeights(contentHeight: 50, chromeHeight: 150)
    #expect(viewModel.windowHeight == 400)

    viewModel.updateLayoutHeights(contentHeight: 348, chromeHeight: 150)
    #expect(viewModel.windowHeight == 500)

    viewModel.updateLayoutHeights(contentHeight: 1_000, chromeHeight: 150)
    #expect(viewModel.windowHeight == 800)

    viewModel.newConversation()
    #expect(viewModel.windowHeight == 400)
}

@Test
func streamingHeightPolicyRequiresFortyPointsAndThrottlesGrowthForThreeHundredMilliseconds() {
    let start = Date(timeIntervalSince1970: 1_000)
    var policy = StreamingHeightPolicy()

    #expect(policy.observe(currentHeight: 400, targetHeight: 439, now: start) == .none)
    #expect(policy.observe(currentHeight: 400, targetHeight: 440, now: start) == .apply(440))
    #expect(policy.observe(currentHeight: 440, targetHeight: 420, now: start.addingTimeInterval(0.1)) == .none)
    if case .schedule(let delay) = policy.observe(
        currentHeight: 440,
        targetHeight: 500,
        now: start.addingTimeInterval(0.1)
    ) {
        #expect(abs(delay - 0.2) < 0.001)
    } else {
        Issue.record("Expected the second growth to be scheduled")
    }
    if case .schedule(let delay) = policy.observe(
        currentHeight: 440,
        targetHeight: 540,
        now: start.addingTimeInterval(0.2)
    ) {
        #expect(abs(delay - 0.1) < 0.001)
    } else {
        Issue.record("Expected the latest growth to remain scheduled")
    }
    #expect(policy.flush(currentHeight: 440, now: start.addingTimeInterval(0.3)) == 540)
    #expect(policy.flush(currentHeight: 540, now: start.addingTimeInterval(0.4)) == nil)
}

@Test @MainActor
func streamingHeightOnlyGrowsAndFinalLayoutSettlesExactly() {
    let viewModel = makeViewModel(messages: [ChatMessage(role: .user, content: "Question")])
    let start = Date(timeIntervalSince1970: 2_000)
    viewModel.beginActiveTimeline()
    viewModel.handle(.contentDelta("A"))

    viewModel.updateLayoutHeights(contentHeight: 338, chromeHeight: 100, now: start)
    #expect(viewModel.windowHeight == 440)

    viewModel.updateLayoutHeights(contentHeight: 298, chromeHeight: 100, now: start.addingTimeInterval(0.1))
    #expect(viewModel.windowHeight == 440)

    viewModel.handle(.finished([
        ChatMessage(role: .user, content: "Question"),
        ChatMessage(role: .assistant, content: "A")
    ]))
    viewModel.updateLayoutHeights(contentHeight: 298, chromeHeight: 100, now: start.addingTimeInterval(0.2))
    #expect(viewModel.windowHeight == 400)
}
