import Foundation

public protocol DeepSeekStreaming: Sendable {
    func stream(messages: [ChatMessage], apiKey: String) -> AsyncThrowingStream<ModelStreamEvent, Error>
}

public struct DeepSeekClient: DeepSeekStreaming, Sendable {
    public static let endpoint = URL(string: "https://api.deepseek.com/v1/chat/completions")!

    private let session: URLSession
    private let endpoint: URL

    public init(session: URLSession = .shared, endpoint: URL = Self.endpoint) {
        self.session = session
        self.endpoint = endpoint
    }

    public func stream(messages: [ChatMessage], apiKey: String) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(
                        DeepSeekRequestBody(messages: messages, context: .current())
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
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        for payload in parser.feed(Data([byte])) {
                            try Self.emit(payload: payload, into: continuation)
                        }
                    }
                    for payload in parser.finish() {
                        try Self.emit(payload: payload, into: continuation)
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
        into continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
    ) throws {
        if payload == "[DONE]" {
            continuation.yield(.finished)
            return
        }
        let chunk: StreamChunk
        do {
            chunk = try JSONDecoder().decode(StreamChunk.self, from: Data(payload.utf8))
        } catch {
            throw SidekickError.invalidResponse("无效的 SSE 数据")
        }
        for choice in chunk.choices {
            if let reasoning = choice.delta.reasoningContent, !reasoning.isEmpty {
                continuation.yield(.reasoningDelta(reasoning))
            }
            if let content = choice.delta.content, !content.isEmpty {
                continuation.yield(.contentDelta(content))
            }
            for call in choice.delta.toolCalls ?? [] {
                continuation.yield(.toolCallDelta(
                    index: call.index,
                    id: call.id,
                    name: call.function?.name,
                    arguments: call.function?.arguments
                ))
            }
            if choice.finishReason != nil { continuation.yield(.finished) }
        }
    }
}

struct DeepSeekRequestBody: Encodable {
    let model = "deepseek-v4-flash"
    let messages: [APIMessage]
    let stream = true
    let thinking = Thinking(type: "enabled")
    let reasoningEffort = "high"
    let tools = [ToolDefinition.webSearch]

    init(messages: [ChatMessage], context: SystemPromptContext) {
        let system = ChatMessage(
            role: .system,
            content: SidekickSystemPrompt.render(context: context)
        )
        let conversation = messages.filter { $0.role != .system }
        self.messages = ([system] + conversation).map(APIMessage.init)
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, thinking, tools
        case reasoningEffort = "reasoning_effort"
    }
}

struct Thinking: Encodable { let type: String }

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
}
