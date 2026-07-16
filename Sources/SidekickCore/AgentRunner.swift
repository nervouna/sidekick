import Foundation

public struct AgentRunner: Sendable {
    private let deepSeek: any DeepSeekStreaming
    private let tavily: any TavilySearching
    private let maxToolRounds: Int

    public init(
        deepSeek: any DeepSeekStreaming = DeepSeekClient(),
        tavily: any TavilySearching = TavilyClient(),
        maxToolRounds: Int = 4
    ) {
        self.deepSeek = deepSeek
        self.tavily = tavily
        self.maxToolRounds = maxToolRounds
    }

    public func run(
        messages initialMessages: [ChatMessage],
        deepSeekKey: String,
        tavilyKey: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var messages = initialMessages
                    var toolRounds = 0

                    while true {
                        try Task.checkCancellation()
                        var content = ""
                        var reasoning = ""
                        var builders: [Int: ToolCallBuilder] = [:]
                        var reasoningActive = false
                        var reasoningCompleted = false
                        var toolStatusShown = false

                        for try await event in deepSeek.stream(messages: messages, apiKey: deepSeekKey) {
                            try Task.checkCancellation()
                            switch event {
                            case .reasoningDelta(let delta):
                                if !reasoningActive {
                                    reasoningActive = true
                                    continuation.yield(.thinkingStarted)
                                }
                                reasoning += delta
                            case .contentDelta(let delta):
                                if reasoningActive && !reasoningCompleted {
                                    reasoningCompleted = true
                                    continuation.yield(.thinkingCompleted)
                                }
                                content += delta
                                continuation.yield(.contentDelta(delta))
                            case .toolCallDelta(let index, let id, let name, let arguments):
                                if reasoningActive && !reasoningCompleted {
                                    reasoningCompleted = true
                                    continuation.yield(.thinkingCompleted)
                                }
                                if !toolStatusShown {
                                    toolStatusShown = true
                                    continuation.yield(.toolCallStarted)
                                }
                                var builder = builders[index] ?? ToolCallBuilder()
                                if let id { builder.id = id }
                                if let name { builder.name += name }
                                if let arguments { builder.arguments += arguments }
                                builders[index] = builder
                            case .finished:
                                break
                            }
                        }

                        if reasoningActive && !reasoningCompleted {
                            continuation.yield(.thinkingCompleted)
                        }
                        let calls = try builders.keys.sorted().map { try builders[$0]!.build() }
                        let assistant = ChatMessage(
                            role: .assistant,
                            content: content,
                            reasoningContent: reasoning.isEmpty ? nil : reasoning,
                            toolCalls: calls.isEmpty ? nil : calls
                        )
                        messages.append(assistant)

                        if calls.isEmpty {
                            continuation.yield(.finished(messages))
                            continuation.finish()
                            return
                        }
                        guard toolRounds < maxToolRounds else { throw SidekickError.toolRoundLimit }
                        toolRounds += 1

                        for call in calls {
                            guard call.function.name == "web_search",
                                  let arguments = try? JSONDecoder().decode(
                                    WebSearchArguments.self,
                                    from: Data(call.function.arguments.utf8)
                                  ),
                                  !arguments.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            else { throw SidekickError.invalidToolArguments }
                            let results = try await tavily.search(query: arguments.query, apiKey: tavilyKey)
                            let resultData = try JSONEncoder().encode(results)
                            let resultString = String(data: resultData, encoding: .utf8) ?? "[]"
                            messages.append(ChatMessage(
                                role: .tool,
                                content: resultString,
                                toolCallID: call.id
                            ))
                        }
                        continuation.yield(.toolCallCompleted)
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: SidekickError.cancelled)
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct WebSearchArguments: Decodable { let query: String }

private struct ToolCallBuilder {
    var id = ""
    var name = ""
    var arguments = ""

    func build() throws -> ToolCall {
        guard !id.isEmpty, !name.isEmpty else {
            throw SidekickError.invalidResponse("工具调用缺少 id 或名称")
        }
        return ToolCall(id: id, function: ToolFunction(name: name, arguments: arguments))
    }
}
