import Foundation
import Testing
@testable import SidekickCore

private final class SequencedDeepSeek: DeepSeekStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var sequences: [[ModelStreamEvent]]
    private(set) var receivedMessages: [[ChatMessage]] = []

    init(_ sequences: [[ModelStreamEvent]]) { self.sequences = sequences }

    func stream(messages: [ChatMessage], apiKey: String) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        lock.lock()
        receivedMessages.append(messages)
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

@Test func agentPreservesReasoningAndToolMessagesAcrossRounds() async throws {
    let deepSeek = SequencedDeepSeek([
        [
            .reasoningDelta("hidden reasoning"),
            .toolCallDelta(index: 0, id: "call-1", name: "web_search", arguments: "{\"query\":\"latest news\"}"),
            .finished
        ],
        [
            .reasoningDelta("final reasoning"),
            .contentDelta("Final [source](https://example.com)"),
            .finished
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

    let secondRequest = deepSeek.receivedMessages[1]
    #expect(secondRequest[1].reasoningContent == "hidden reasoning")
    #expect(secondRequest[2].role == .tool)
    #expect(events.contains(.toolCallStarted))
    #expect(events.contains(.toolCallCompleted))
}

@Test func directAnswerStreamsWithoutSearch() async throws {
    let deepSeek = SequencedDeepSeek([[
        .reasoningDelta("hidden"),
        .contentDelta("Hello"),
        .finished
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
