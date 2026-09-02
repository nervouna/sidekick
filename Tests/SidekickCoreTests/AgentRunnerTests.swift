import Foundation
import Testing
@testable import SidekickCore

private final class SequencedDeepSeek: DeepSeekStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var sequences: [[ModelStreamEvent]]
    private(set) var receivedRequests: [ModelRequest] = []

    init(_ sequences: [[ModelStreamEvent]]) { self.sequences = sequences }

    func stream(request: ModelRequest, apiKey: String) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        lock.lock()
        receivedRequests.append(request)
        let sequence = sequences.removeFirst()
        lock.unlock()
        return AsyncThrowingStream { continuation in
            sequence.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

private struct FixedTavily: TavilySearching {
    func search(query: String, apiKey: String) async throws -> [TavilyResult] {
        #expect(query == "latest news")
        return [TavilyResult(title: "Source", url: "https://example.com", content: "Result", score: 0.9)]
    }
}

private actor CountingTavily: TavilySearching {
    private(set) var queries: [String] = []

    func search(query: String, apiKey: String) async throws -> [TavilyResult] {
        queries.append(query)
        return [TavilyResult(
            title: query,
            url: "https://example.com/\(query)",
            content: "evidence",
            score: 1
        )]
    }
}

@Test func agentPreservesReasoningAndToolMessagesAcrossRounds() async throws {
    let deepSeek = SequencedDeepSeek([
        [
            .reasoningDelta("hidden reasoning"),
            .toolCallDelta(index: 0, id: "call-1", name: "web_search", arguments: "{\"query\":\"latest news\"}"),
            .finished(.toolCalls)
        ],
        [
            .reasoningDelta("final reasoning"),
            .contentDelta("Final [source](https://example.com)"),
            .finished(.stop)
        ]
    ])
    let runner = AgentRunner(deepSeek: deepSeek, tavily: FixedTavily())
    let user = ChatMessage(role: .user, content: "question")
    var events: [AgentEvent] = []
    for try await event in runner.run(messages: [user], deepSeekKey: "d", tavilyKey: "t") {
        events.append(event)
    }

    guard case .finished(let messages) = events.last else {
        Issue.record("Agent did not finish")
        return
    }
    #expect(messages.count == 4)
    #expect(messages[1].reasoningContent == "hidden reasoning")
    #expect(messages[1].toolCalls?.first?.id == "call-1")
    #expect(messages[2].role == .tool)
    #expect(messages[2].toolCallID == "call-1")
    #expect(messages[2].content?.contains("example.com") == true)
    #expect(messages[3].content == "Final [source](https://example.com)")

    let secondRequest = deepSeek.receivedRequests[1].conversationMessages
    #expect(secondRequest[1].reasoningContent == "hidden reasoning")
    #expect(secondRequest[2].role == .tool)
    #expect(events.contains(.toolCallStarted))
    #expect(events.contains(.toolCallCompleted))
}

@Test func directAnswerStreamsWithoutSearch() async throws {
    let deepSeek = SequencedDeepSeek([[
        .reasoningDelta("hidden"),
        .contentDelta("Hello"),
        .finished(.stop)
    ]])
    let runner = AgentRunner(deepSeek: deepSeek, tavily: FixedTavily())
    var events: [AgentEvent] = []
    for try await event in runner.run(
        messages: [ChatMessage(role: .user, content: "hi")],
        deepSeekKey: "d",
        tavilyKey: "t"
    ) { events.append(event) }
    #expect(events.contains(.thinkingStarted))
    #expect(events.contains(.thinkingCompleted))
    #expect(events.contains(.contentDelta("Hello")))
    #expect(!events.contains(.toolCallStarted))
}

@Test func threeToolCallsExecuteOnlyTwoAndForceFinalWithoutAnotherSearch() async throws {
    let calls = (1...3).map { index in
        ModelStreamEvent.toolCallDelta(
            index: index - 1,
            id: "call-\(index)",
            name: "web_search",
            arguments: #"{"query":"q\#(index)"}"#
        )
    }
    let deepSeek = SequencedDeepSeek([
        calls + [.finished(.toolCalls)],
        [.contentDelta("Final with incomplete evidence"), .finished(.stop)]
    ])
    let tavily = CountingTavily()
    let runner = AgentRunner(deepSeek: deepSeek, tavily: tavily)
    var finalMessages: [ChatMessage] = []
    for try await event in runner.run(
        messages: [ChatMessage(role: .user, content: "question")],
        deepSeekKey: "d",
        tavilyKey: "t"
    ) {
        if case .finished(let messages) = event { finalMessages = messages }
    }

    let queries = await tavily.queries
    #expect(queries == ["q1", "q2"])
    let tools = finalMessages.filter { $0.role == .tool }
    #expect(tools.map(\.toolCallID) == ["call-1", "call-2", "call-3"])
    #expect(tools.last?.content?.contains("search_limit_reached") == true)
    #expect(deepSeek.receivedRequests.count == 2)
    #expect(deepSeek.receivedRequests[1].options.toolChoice == .none)
}

@Test func finishReasonLengthMarksFinalMessageTruncatedAndDropsReasoning() async throws {
    let deepSeek = SequencedDeepSeek([[
        .reasoningDelta("private"),
        .contentDelta("partial"),
        .finished(.length)
    ]])
    let runner = AgentRunner(deepSeek: deepSeek, tavily: FixedTavily())
    var finalMessages: [ChatMessage] = []
    for try await event in runner.run(
        messages: [ChatMessage(role: .user, content: "question")],
        deepSeekKey: "d",
        tavilyKey: "t"
    ) {
        if case .finished(let messages) = event { finalMessages = messages }
    }
    #expect(finalMessages.last?.completionState == .truncated)
    #expect(finalMessages.last?.reasoningContent == nil)
}

@Test func searchBudgetExhaustionReturnsMatchingToolErrorWithoutCallingTavily() async throws {
    let hugeQuery = String(repeating: "q", count: 4_000)
    let deepSeek = SequencedDeepSeek([
        [
            .toolCallDelta(
                index: 0,
                id: "oversized-call",
                name: "web_search",
                arguments: #"{"query":"\#(hugeQuery)"}"#
            ),
            .finished(.toolCalls)
        ],
        [.contentDelta("Final"), .finished(.stop)]
    ])
    let tavily = CountingTavily()
    let runner = AgentRunner(deepSeek: deepSeek, tavily: tavily)
    let largeUser = ChatMessage(role: .user, content: String(repeating: "u", count: 9_000))
    var finalMessages: [ChatMessage] = []
    for try await event in runner.run(
        messages: [largeUser],
        deepSeekKey: "d",
        tavilyKey: "t"
    ) {
        if case .finished(let messages) = event { finalMessages = messages }
    }

    let queries = await tavily.queries
    #expect(queries.isEmpty)
    let tool = finalMessages.first { $0.role == .tool }
    #expect(tool?.toolCallID == "oversized-call")
    #expect(tool?.content?.contains("search_budget_exhausted") == true)
    #expect(deepSeek.receivedRequests.last?.options.toolChoice == ToolChoice.none)
}

private struct ThrowingTavily: TavilySearching {
    func search(query: String, apiKey: String) async throws -> [TavilyResult] {
        throw SidekickError.http(status: 503, message: "unavailable")
    }
}

@Test func tavilyFailureReturnsSearchFailedAndStillFinishes() async throws {
    let deepSeek = SequencedDeepSeek([
        [
            .toolCallDelta(
                index: 0,
                id: "call-1",
                name: "web_search",
                arguments: #"{"query":"latest news"}"#
            ),
            .finished(.toolCalls)
        ],
        [.contentDelta("Final with incomplete evidence"), .finished(.stop)]
    ])
    let runner = AgentRunner(deepSeek: deepSeek, tavily: ThrowingTavily())
    var events: [AgentEvent] = []
    var finalMessages: [ChatMessage] = []
    for try await event in runner.run(
        messages: [ChatMessage(role: .user, content: "question")],
        deepSeekKey: "d",
        tavilyKey: "t"
    ) {
        events.append(event)
        if case .finished(let messages) = event { finalMessages = messages }
    }

    #expect(events.contains(.toolCallStarted))
    #expect(events.contains(.toolCallCompleted))
    let tool = finalMessages.first { $0.role == .tool }
    #expect(tool?.toolCallID == "call-1")
    #expect(tool?.content?.contains("search_failed") == true)
    #expect(finalMessages.last?.content == "Final with incomplete evidence")
    #expect(deepSeek.receivedRequests.count == 2)
    #expect(deepSeek.receivedRequests[1].options.toolChoice == .none)
}

@Test func invalidToolCallReturnsInvalidSearchRequestWithoutCallingTavily() async throws {
    let deepSeek = SequencedDeepSeek([
        [
            .toolCallDelta(
                index: 0,
                id: "bad-call",
                name: "web_search",
                arguments: #"{"query":"   "}"#
            ),
            .finished(.toolCalls)
        ],
        [.contentDelta("Final"), .finished(.stop)]
    ])
    let tavily = CountingTavily()
    let runner = AgentRunner(deepSeek: deepSeek, tavily: tavily)
    var finalMessages: [ChatMessage] = []
    for try await event in runner.run(
        messages: [ChatMessage(role: .user, content: "question")],
        deepSeekKey: "d",
        tavilyKey: "t"
    ) {
        if case .finished(let messages) = event { finalMessages = messages }
    }

    let queries = await tavily.queries
    #expect(queries.isEmpty)
    let tool = finalMessages.first { $0.role == .tool }
    #expect(tool?.toolCallID == "bad-call")
    #expect(tool?.content?.contains("invalid_search_request") == true)
    #expect(deepSeek.receivedRequests.last?.options.toolChoice == ToolChoice.none)
}

private struct URLCancelledTavily: TavilySearching {
    func search(query: String, apiKey: String) async throws -> [TavilyResult] {
        throw URLError(.cancelled)
    }
}

@Test func tavilyURLCancellationDoesNotBecomeSearchFailed() async {
    let deepSeek = SequencedDeepSeek([
        [
            .toolCallDelta(
                index: 0,
                id: "call-1",
                name: "web_search",
                arguments: #"{"query":"latest news"}"#
            ),
            .finished(.toolCalls)
        ],
        [.contentDelta("Should not run"), .finished(.stop)]
    ])
    let runner = AgentRunner(deepSeek: deepSeek, tavily: URLCancelledTavily())
    var events: [AgentEvent] = []
    do {
        for try await event in runner.run(
            messages: [ChatMessage(role: .user, content: "question")],
            deepSeekKey: "d",
            tavilyKey: "t"
        ) {
            events.append(event)
        }
        Issue.record("cancelled search should throw")
    } catch {
        #expect(error as? SidekickError == .cancelled)
    }

    #expect(events.contains(.toolCallStarted))
    #expect(!events.contains(.toolCallCompleted))
    #expect(!events.contains { event in
        if case .failed = event { return true }
        return false
    })
    #expect(!events.contains { event in
        if case .finished = event { return true }
        return false
    })
    #expect(deepSeek.receivedRequests.count == 1)
}
