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
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String? = nil,
        reasoningContent: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.createdAt = createdAt
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
    case finished
}

public enum AgentEvent: Equatable, Sendable {
    case thinkingStarted
    case thinkingCompleted
    case contentDelta(String)
    case toolCallStarted
    case toolCallCompleted
    case finished([ChatMessage])
    case failed(String)
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
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingKey(let service): return "缺少 \(service) API Key"
        case .invalidResponse(let message): return "响应解析失败：\(message)"
        case .http(let status, let message): return "请求失败（HTTP \(status)）：\(message)"
        case .invalidToolArguments: return "网页搜索参数无效"
        case .toolRoundLimit: return "网页搜索次数已达到本轮上限，请缩小问题范围后重试"
        case .cancelled: return "请求已取消"
        }
    }
}
