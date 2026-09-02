import Foundation

public enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct ToolFunction: Codable, Equatable, Sendable {
    public var name: String
    public var arguments: String

    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
}

public struct ToolCall: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: String
    public var function: ToolFunction

    public init(id: String, type: String = "function", function: ToolFunction) {
        self.id = id
        self.type = type
        self.function = function
    }
}

public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var role: MessageRole
    public var content: String?
    public var reasoningContent: String?
    public var toolCalls: [ToolCall]?
    public var toolCallID: String?
    public var attachedContext: String?
    public var completionState: AssistantCompletionState?
    public var createdAt: Date
    public var responseEndedAt: Date?
    public var tokenCount: Int?

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String? = nil,
        reasoningContent: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallID: String? = nil,
        attachedContext: String? = nil,
        completionState: AssistantCompletionState? = nil,
        createdAt: Date = Date(),
        responseEndedAt: Date? = nil,
        tokenCount: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.attachedContext = attachedContext
        self.completionState = completionState
        self.createdAt = createdAt
        self.responseEndedAt = responseEndedAt
        self.tokenCount = tokenCount
    }
}

public enum AttachedContext {
    public static let truncationMarker = "\n[已截断]"

    public static func clamp(_ text: String) -> (text: String, truncated: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", false) }
        guard trimmed.count > ContextPolicy.attachedContextCharacterLimit else {
            return (trimmed, false)
        }
        let prefix = String(trimmed.prefix(ContextPolicy.attachedContextCharacterLimit))
        return (prefix + truncationMarker, true)
    }

    public static func embed(question: String?, clipboard: String) -> String {
        let question = question ?? ""
        return """
        \(question)

        <attached_context source="clipboard">
        \(clipboard)
        </attached_context>
        """
    }
}

public enum AssistantCompletionState: String, Codable, Equatable, Sendable {
    case complete
    case cancelled
    case truncated
    case filtered
    case interrupted
}

public enum ModelFinishReason: String, Codable, Equatable, Sendable {
    case stop
    case length
    case toolCalls = "tool_calls"
    case contentFilter = "content_filter"
    case insufficientSystemResource = "insufficient_system_resource"
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var reasoningTokens: Int
    public var cacheHitTokens: Int
    public var cacheMissTokens: Int
    public var totalTokens: Int

    public init(
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        reasoningTokens: Int = 0,
        cacheHitTokens: Int = 0,
        cacheMissTokens: Int = 0,
        totalTokens: Int = 0
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.cacheHitTokens = cacheHitTokens
        self.cacheMissTokens = cacheMissTokens
        self.totalTokens = totalTokens
    }
}

public enum ToolChoice: String, Codable, Equatable, Sendable {
    case auto
    case none
}

public struct DeepSeekRequestOptions: Equatable, Sendable {
    public var maxTokens: Int
    public var toolChoice: ToolChoice
    public var includeUsage: Bool

    public init(maxTokens: Int, toolChoice: ToolChoice = .auto, includeUsage: Bool = true) {
        self.maxTokens = maxTokens
        self.toolChoice = toolChoice
        self.includeUsage = includeUsage
    }
}

public struct ModelRequest: Equatable, Sendable {
    public var systemPrompt: String
    public var conversationMessages: [ChatMessage]
    public var options: DeepSeekRequestOptions

    public init(
        systemPrompt: String,
        conversationMessages: [ChatMessage],
        maxTokens: Int,
        toolChoice: ToolChoice = .auto,
        includeUsage: Bool = true
    ) {
        self.systemPrompt = systemPrompt
        self.conversationMessages = conversationMessages
        options = DeepSeekRequestOptions(
            maxTokens: maxTokens,
            toolChoice: toolChoice,
            includeUsage: includeUsage
        )
    }
}

public struct ChatSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var lastMessageAt: Date?
    public var messages: [ChatMessage]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        lastMessageAt: Date? = nil,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastMessageAt = lastMessageAt
        self.messages = messages
    }

    public mutating func append(_ message: ChatMessage, now: Date = Date()) {
        messages.append(message)
        lastMessageAt = now
    }
}

public enum ModelStreamEvent: Equatable, Sendable {
    case reasoningDelta(String)
    case contentDelta(String)
    case toolCallDelta(index: Int, id: String?, name: String?, arguments: String?)
    case usage(TokenUsage)
    case finished(ModelFinishReason)
}

public enum AgentEvent: Equatable, Sendable {
    case thinkingStarted
    case thinkingCompleted
    case contentDelta(String)
    case toolCallStarted
    case toolCallCompleted
    case usage(TokenUsage, estimatedPromptTokens: Int)
    case contextPrepared([ChatMessage], evictedMessageIDs: Set<UUID>)
    case finished([ChatMessage])
    case failed(String, [ChatMessage]?)
}

public struct TavilyResult: Codable, Equatable, Sendable {
    public var title: String
    public var url: String
    public var content: String
    public var score: Double
    public var publishedDate: String?

    public init(title: String, url: String, content: String, score: Double, publishedDate: String? = nil) {
        self.title = title
        self.url = url
        self.content = content
        self.score = score
        self.publishedDate = publishedDate
    }
}

public enum SidekickError: LocalizedError, Equatable, Sendable {
    case missingKey(String)
    case invalidResponse(String)
    case http(status: Int, message: String)
    case invalidToolArguments
    case toolRoundLimit
    case contextBudgetExceeded
    case userInputTooLong
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingKey(let service): return "缺少 \(service) API Key"
        case .invalidResponse(let message): return "响应解析失败：\(message)"
        case .http(let status, let message): return "请求失败（HTTP \(status)）：\(message)"
        case .invalidToolArguments: return "网页搜索参数无效"
        case .toolRoundLimit: return "网页搜索次数已达到本轮上限，请缩小问题范围后重试"
        case .contextBudgetExceeded: return "本轮上下文已达到预算上限，请缩小问题后重试"
        case .userInputTooLong: return "问题不能超过 1000 个字符"
        case .cancelled: return "请求已取消"
        }
    }
}
