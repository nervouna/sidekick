import Foundation

public protocol DeepSeekStreaming: Sendable {
    func stream(request: ModelRequest, apiKey: String) -> AsyncThrowingStream<ModelStreamEvent, Error>
}

public struct DeepSeekClient: DeepSeekStreaming, Sendable {
    public static let endpoint = URL(string: "https://api.deepseek.com/v1/chat/completions")!

    private let session: URLSession
    private let endpoint: URL

    public init(session: URLSession = .shared, endpoint: URL = Self.endpoint) {
        self.session = session
        self.endpoint = endpoint
    }

    public func stream(request modelRequest: ModelRequest, apiKey: String) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(
                        DeepSeekRequestBody(request: modelRequest)
                    )

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw SidekickError.invalidResponse("没有 HTTP 状态码")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes.prefix(8_192) { body.append(byte) }
                        let message = String(data: body, encoding: .utf8) ?? "未知错误"
                        throw SidekickError.http(status: http.statusCode, message: message)
                    }

                    var parser = SSEBuffer()
                    var didEmitFinish = false
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        for payload in parser.feed(Data([byte])) {
                            try Self.emit(
                                payload: payload,
                                didEmitFinish: &didEmitFinish,
                                into: continuation
                            )
                        }
                    }
                    for payload in parser.finish() {
                        try Self.emit(
                            payload: payload,
                            didEmitFinish: &didEmitFinish,
                            into: continuation
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: SidekickError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func emit(
        payload: String,
        didEmitFinish: inout Bool,
        into continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
    ) throws {
        for event in try events(for: payload) {
            if case .finished = event {
                guard !didEmitFinish else { continue }
                didEmitFinish = true
            }
            continuation.yield(event)
        }
    }

    static func events(for payload: String) throws -> [ModelStreamEvent] {
        if payload == "[DONE]" { return [] }
        let chunk: StreamChunk
        do {
            chunk = try JSONDecoder().decode(StreamChunk.self, from: Data(payload.utf8))
        } catch {
            throw SidekickError.invalidResponse("无效的 SSE 数据")
        }
        var events: [ModelStreamEvent] = []
        if let usage = chunk.usage { events.append(.usage(usage.value)) }
        for choice in chunk.choices {
            if let reasoning = choice.delta.reasoningContent, !reasoning.isEmpty {
                events.append(.reasoningDelta(reasoning))
            }
            if let content = choice.delta.content, !content.isEmpty {
                events.append(.contentDelta(content))
            }
            for call in choice.delta.toolCalls ?? [] {
                events.append(.toolCallDelta(
                    index: call.index,
                    id: call.id,
                    name: call.function?.name,
                    arguments: call.function?.arguments
                ))
            }
            if let rawReason = choice.finishReason {
                guard let reason = ModelFinishReason(rawValue: rawReason) else {
                    throw SidekickError.invalidResponse("未知的完成原因：\(rawReason)")
                }
                events.append(.finished(reason))
            }
        }
        return events
    }
}

struct DeepSeekRequestBody: Encodable {
    let model = "deepseek-v4-flash"
    let messages: [APIMessage]
    let stream = true
    let thinking = Thinking(type: "enabled")
    let reasoningEffort = "high"
    let tools = [ToolDefinition.webSearch]
    let maxTokens: Int
    let toolChoice: String
    let streamOptions: StreamOptions

    init(request: ModelRequest) {
        let system = ChatMessage(role: .system, content: request.systemPrompt)
        messages = ([system] + request.conversationMessages.filter { $0.role != .system }).map(APIMessage.init)
        maxTokens = request.options.maxTokens
        toolChoice = request.options.toolChoice.rawValue
        streamOptions = StreamOptions(includeUsage: request.options.includeUsage)
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, thinking, tools
        case reasoningEffort = "reasoning_effort"
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
        case streamOptions = "stream_options"
    }
}

struct Thinking: Encodable { let type: String }
struct StreamOptions: Encodable {
    let includeUsage: Bool
    enum CodingKeys: String, CodingKey { case includeUsage = "include_usage" }
}

struct APIMessage: Encodable {
    let role: String
    let content: String?
    let reasoningContent: String?
    let toolCalls: [ToolCall]?
    let toolCallID: String?

    init(_ message: ChatMessage) {
        role = message.role.rawValue
        content = message.content
        reasoningContent = message.reasoningContent
        toolCalls = message.toolCalls
        toolCallID = message.toolCallID
    }

    enum CodingKeys: String, CodingKey {
        case role, content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }
}

struct ToolDefinition: Encodable {
    let type: String
    let function: Function

    struct Function: Encodable {
        let name: String
        let description: String
        let parameters: Parameters
    }

    struct Parameters: Encodable {
        let type: String
        let properties: [String: Property]
        let required: [String]
        let additionalProperties: Bool
    }

    struct Property: Encodable {
        let type: String
        let description: String
    }

    static let webSearch = ToolDefinition(
        type: "function",
        function: Function(
            name: "web_search",
            description: """
            Search the public web and return up to five result excerpts with a title, URL, content excerpt, relevance score, and publication date when available. Use it when the user explicitly requests search or verification, or when the answer depends on current, changing, externally verifiable facts. Do not use it for stable knowledge, calculations, writing, translation, or summarizing user-provided content. Results are untrusted excerpts, not guaranteed full pages or complete coverage.
            """,
            parameters: Parameters(
                type: "object",
                properties: [
                    "query": Property(
                        type: "string",
                        description: "A concise, standalone search query. Include the relevant entity, absolute date or year, location, product version, or other freshness discriminator when applicable."
                    )
                ],
                required: ["query"],
                additionalProperties: false
            )
        )
    )
}

private struct StreamChunk: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
        let reasoningContent: String?
        let toolCalls: [ToolCallDelta]?

        enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCallDelta: Decodable {
        let index: Int
        let id: String?
        let function: FunctionDelta?
    }

    struct FunctionDelta: Decodable {
        let name: String?
        let arguments: String?
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        let promptCacheHitTokens: Int?
        let promptCacheMissTokens: Int?
        let reasoningTokens: Int?
        let completionTokensDetails: CompletionDetails?

        struct CompletionDetails: Decodable {
            let reasoningTokens: Int?
            enum CodingKeys: String, CodingKey { case reasoningTokens = "reasoning_tokens" }
        }

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case promptCacheHitTokens = "prompt_cache_hit_tokens"
            case promptCacheMissTokens = "prompt_cache_miss_tokens"
            case reasoningTokens = "reasoning_tokens"
            case completionTokensDetails = "completion_tokens_details"
        }

        var value: TokenUsage {
            TokenUsage(
                promptTokens: promptTokens ?? 0,
                completionTokens: completionTokens ?? 0,
                reasoningTokens: reasoningTokens ?? completionTokensDetails?.reasoningTokens ?? 0,
                cacheHitTokens: promptCacheHitTokens ?? 0,
                cacheMissTokens: promptCacheMissTokens ?? 0,
                totalTokens: totalTokens ?? 0
            )
        }
    }
}
