import Foundation

public struct AgentRunner: Sendable {
    private let deepSeek: any DeepSeekStreaming
    private let tavily: any TavilySearching
    private let contextManager: ContextManager

    public init(
        deepSeek: any DeepSeekStreaming = DeepSeekClient(),
        tavily: any TavilySearching = TavilyClient(),
        contextManager: ContextManager = ContextManager()
    ) {
        self.deepSeek = deepSeek
        self.tavily = tavily
        self.contextManager = contextManager
    }

    public func run(
        messages: [ChatMessage],
        deepSeekKey: String,
        tavilyKey: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        do {
            let prompt = SidekickSystemPrompt.render(context: .current())
            let prepared = try contextManager.prepare(
                systemPrompt: prompt,
                messages: messages,
                estimator: ContextEstimator()
            )
            return run(prepared: prepared, deepSeekKey: deepSeekKey, tavilyKey: tavilyKey)
        } catch {
            return AsyncThrowingStream { continuation in continuation.finish(throwing: error) }
        }
    }

    public func run(
        prepared initialPrepared: PreparedConversation,
        correctionFactor: Double = 1.0,
        deepSeekKey: String,
        tavilyKey: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var messages = initialPrepared.conversationMessages
                var prepared = initialPrepared
                var estimator = ContextEstimator(correctionFactor: correctionFactor)
                var searchCalls = 0
                var forceFinal = false
                var isToolFollowUp = false
                var partialContent = ""

                do {
                    while true {
                        try Task.checkCancellation()
                        let request = try prepared.request(
                            toolChoice: forceFinal ? .none : .auto,
                            isToolFollowUp: isToolFollowUp
                        )
                        var content = ""
                        var reasoning = ""
                        var builders: [Int: ToolCallBuilder] = [:]
                        var reasoningActive = false
                        var reasoningCompleted = false
                        var finishReason: ModelFinishReason?
                        partialContent = ""

                        for try await event in deepSeek.stream(request: request, apiKey: deepSeekKey) {
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
                                partialContent = content
                                continuation.yield(.contentDelta(delta))
                            case .toolCallDelta(let index, let id, let name, let arguments):
                                if reasoningActive && !reasoningCompleted {
                                    reasoningCompleted = true
                                    continuation.yield(.thinkingCompleted)
                                }
                                var builder = builders[index] ?? ToolCallBuilder()
                                if let id { builder.id = id }
                                if let name { builder.name += name }
                                if let arguments { builder.arguments += arguments }
                                builders[index] = builder
                            case .usage(let usage):
                                continuation.yield(.usage(usage, estimatedPromptTokens: prepared.estimatedPromptTokens))
                                estimator.observe(
                                    actualPromptTokens: usage.promptTokens,
                                    estimatedPromptTokens: prepared.estimatedPromptTokens
                                )
                            case .finished(let reason):
                                finishReason = reason
                            }
                        }

                        if reasoningActive && !reasoningCompleted {
                            continuation.yield(.thinkingCompleted)
                        }
                        guard let finishReason else {
                            throw SidekickError.invalidResponse("流已结束但缺少 finish_reason")
                        }

                        let calls = try builders.keys.sorted().map { try builders[$0]!.build() }
                        if calls.isEmpty {
                            let state = completionState(for: finishReason)
                            let final = ChatMessage(
                                role: .assistant,
                                content: content,
                                reasoningContent: nil,
                                completionState: state
                            )
                            messages.append(final)
                            if finishReason == .contentFilter && content.isEmpty {
                                continuation.yield(.failed("回答因安全策略未能生成", messages))
                            } else if finishReason == .insufficientSystemResource {
                                continuation.yield(.failed("模型服务暂时中断，请稍后重试", messages))
                            } else {
                                continuation.yield(.finished(messages))
                            }
                            continuation.finish()
                            return
                        }

                        guard finishReason == .toolCalls else {
                            throw SidekickError.invalidResponse("非 tool_calls 完成原因包含工具调用")
                        }
                        messages.append(ChatMessage(
                            role: .assistant,
                            content: content,
                            reasoningContent: reasoning.isEmpty ? nil : reasoning,
                            toolCalls: calls
                        ))

                        for call in calls {
                            guard searchCalls < ContextPolicy.maximumSearchCalls else {
                                messages.append(toolError(
                                    callID: call.id,
                                    code: "search_limit_reached",
                                    message: "This question has reached the two-search limit. Answer from existing evidence and disclose that it may be incomplete."
                                ))
                                forceFinal = true
                                continue
                            }
                            guard call.function.name == "web_search",
                                  let arguments = try? JSONDecoder().decode(
                                    WebSearchArguments.self,
                                    from: Data(call.function.arguments.utf8)
                                  ),
                                  !arguments.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            else {
                                messages.append(toolError(
                                    callID: call.id,
                                    code: "invalid_search_request",
                                    message: "The search request was invalid and could not be executed."
                                ))
                                forceFinal = true
                                continue
                            }

                            let currentEstimate = estimator.promptTokens(
                                systemPrompt: initialPrepared.systemPrompt,
                                messages: messages
                            )
                            let worstCaseSearchResult = ContextPolicy.messageOverheadTokens
                                + ContextPolicy.searchEvidenceTokenBudget
                            guard currentEstimate + worstCaseSearchResult
                                    <= ContextPolicy.totalTokenBudget - ContextPolicy.minimumFinalGenerationTokens
                            else {
                                messages.append(toolError(
                                    callID: call.id,
                                    code: "search_budget_exhausted",
                                    message: "There is not enough context budget for another search. Answer from existing evidence and disclose that it may be incomplete."
                                ))
                                forceFinal = true
                                continue
                            }

                            continuation.yield(.toolCallStarted)
                            searchCalls += 1
                            do {
                                let results = try await tavily.search(query: arguments.query, apiKey: tavilyKey)
                                let evidence = try SearchEvidenceBuilder.encode(results, estimator: estimator)
                                messages.append(ChatMessage(role: .tool, content: evidence, toolCallID: call.id))
                                continuation.yield(.toolCallCompleted)
                                if searchCalls >= ContextPolicy.maximumSearchCalls { forceFinal = true }
                            } catch {
                                if Self.isCancellation(error) {
                                    throw SidekickError.cancelled
                                }
                                messages.append(toolError(
                                    callID: call.id,
                                    code: "search_failed",
                                    message: "The web search failed and could not be completed. Answer from existing evidence and disclose that it may be incomplete."
                                ))
                                continuation.yield(.toolCallCompleted)
                                forceFinal = true
                            }
                        }

                        do {
                            prepared = try contextManager.prepareToolFollowUp(
                                systemPrompt: initialPrepared.systemPrompt,
                                messages: messages,
                                estimator: estimator
                            )
                        } catch SidekickError.contextBudgetExceeded {
                            messages.append(ChatMessage(
                                role: .assistant,
                                completionState: .interrupted
                            ))
                            continuation.yield(.failed(
                                SidekickError.contextBudgetExceeded.localizedDescription,
                                messages
                            ))
                            continuation.finish()
                            return
                        }
                        messages = prepared.conversationMessages
                        continuation.yield(.contextPrepared(
                            messages,
                            evictedMessageIDs: prepared.evictedMessageIDs
                        ))
                        isToolFollowUp = true
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: SidekickError.cancelled)
                } catch let error as SidekickError where error == .cancelled {
                    continuation.finish(throwing: error)
                } catch {
                    if !partialContent.isEmpty {
                        messages.append(ChatMessage(
                            role: .assistant,
                            content: partialContent,
                            completionState: .interrupted
                        ))
                    } else if messages.last?.role != .assistant || messages.last?.completionState == nil {
                        messages.append(ChatMessage(role: .assistant, completionState: .interrupted))
                    }
                    continuation.yield(.failed(error.localizedDescription, messages))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func completionState(for reason: ModelFinishReason) -> AssistantCompletionState {
        switch reason {
        case .stop: .complete
        case .length: .truncated
        case .contentFilter: .filtered
        case .insufficientSystemResource, .toolCalls: .interrupted
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled { return true }
        if error is CancellationError { return true }
        if error as? SidekickError == .cancelled { return true }
        if (error as? URLError)?.code == .cancelled { return true }
        return false
    }

    private func toolError(callID: String, code: String, message: String) -> ChatMessage {
        ChatMessage(
            role: .tool,
            content: ToolErrorPayload.encoded(code: code, message: message),
            toolCallID: callID
        )
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
