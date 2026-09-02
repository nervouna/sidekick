import Foundation

public enum ContextPolicy {
    public static let totalTokenBudget = 16_384
    public static let initialInputTarget = 12_288
    public static let preferredGenerationTokens = 4_096
    public static let minimumFinalGenerationTokens = 512
    public static let userCharacterLimit = 1_000
    public static let attachedContextCharacterLimit = 4_000
    public static let characterCountDisplayThreshold = 800
    public static let maximumSearchCalls = 2
    public static let searchEvidenceTokenBudget = 2_048
    public static let sessionExpiry: TimeInterval = 30 * 60

    public static let messageOverheadTokens = 24
    public static let toolCallOverheadTokens = 64
    public static let estimateSafetyMultiplier = 1.25
    public static let scalarTokenRatio = 0.75
    public static let utf8ByteTokenRatio = 0.5
    public static let correctionHeadroom = 1.10
    public static let maximumCorrectionFactor = 4.0
}

public struct ContextEstimator: Equatable, Sendable {
    public private(set) var correctionFactor: Double

    public init(correctionFactor: Double = 1.0) {
        self.correctionFactor = min(
            ContextPolicy.maximumCorrectionFactor,
            max(1.0, correctionFactor)
        )
    }

    public static func rawTextTokens(_ text: String) -> Int {
        let scalars = Double(text.unicodeScalars.count) * ContextPolicy.scalarTokenRatio
        let bytes = Double(text.utf8.count) * ContextPolicy.utf8ByteTokenRatio
        return Int(ceil(max(scalars, bytes) * ContextPolicy.estimateSafetyMultiplier))
    }

    public func textTokens(_ text: String) -> Int {
        Int(ceil(Double(Self.rawTextTokens(text)) * correctionFactor))
    }

    public func messageTokens(_ message: ChatMessage) -> Int {
        var total = ContextPolicy.messageOverheadTokens
        for text in [message.content, message.reasoningContent, message.toolCallID, message.attachedContext].compactMap({ $0 }) {
            total += textTokens(text)
        }
        for call in message.toolCalls ?? [] {
            total += ContextPolicy.toolCallOverheadTokens
            total += textTokens(call.id)
            total += textTokens(call.type)
            total += textTokens(call.function.name)
            total += textTokens(call.function.arguments)
        }
        return total
    }

    public func promptTokens(systemPrompt: String, messages: [ChatMessage]) -> Int {
        messageTokens(ChatMessage(role: .system, content: systemPrompt))
            + messages.reduce(0) { $0 + messageTokens($1) }
    }

    public mutating func observe(actualPromptTokens: Int, estimatedPromptTokens: Int) {
        guard estimatedPromptTokens > 0, actualPromptTokens > estimatedPromptTokens else { return }
        let candidate = Double(actualPromptTokens) / Double(estimatedPromptTokens)
            * ContextPolicy.correctionHeadroom
        correctionFactor = min(ContextPolicy.maximumCorrectionFactor, max(correctionFactor, candidate))
    }
}

public struct PreparedConversation: Equatable, Sendable {
    public var systemPrompt: String
    public var conversationMessages: [ChatMessage]
    public var estimatedPromptTokens: Int
    public var evictedMessageIDs: Set<UUID>

    public init(
        systemPrompt: String,
        conversationMessages: [ChatMessage],
        estimatedPromptTokens: Int,
        evictedMessageIDs: Set<UUID> = []
    ) {
        self.systemPrompt = systemPrompt
        self.conversationMessages = conversationMessages
        self.estimatedPromptTokens = estimatedPromptTokens
        self.evictedMessageIDs = evictedMessageIDs
    }

    public func request(toolChoice: ToolChoice = .auto, isToolFollowUp: Bool = false) throws -> ModelRequest {
        let available = ContextPolicy.totalTokenBudget - estimatedPromptTokens
        let maxTokens = isToolFollowUp
            ? min(ContextPolicy.preferredGenerationTokens, available)
            : ContextPolicy.preferredGenerationTokens
        guard maxTokens >= ContextPolicy.minimumFinalGenerationTokens else {
            throw SidekickError.contextBudgetExceeded
        }
        return ModelRequest(
            systemPrompt: systemPrompt,
            conversationMessages: conversationMessages,
            maxTokens: maxTokens,
            toolChoice: toolChoice,
            includeUsage: true
        )
    }
}

public struct ContextManager: Sendable {
    public init() {}

    public func prepare(
        systemPrompt: String,
        messages: [ChatMessage],
        estimator: ContextEstimator,
        inputTarget: Int = ContextPolicy.initialInputTarget
    ) throws -> PreparedConversation {
        let source = messages.filter { $0.role != .system }
        let turns = groupTurns(source)
        guard let current = turns.last else {
            let estimate = estimator.promptTokens(systemPrompt: systemPrompt, messages: [])
            guard estimate <= inputTarget else { throw SidekickError.contextBudgetExceeded }
            return PreparedConversation(
                systemPrompt: systemPrompt,
                conversationMessages: [],
                estimatedPromptTokens: estimate
            )
        }

        let normalizedCurrent = normalize(current, allowIncompleteCurrent: true)
        var selected = normalizedCurrent
        var estimate = estimator.promptTokens(systemPrompt: systemPrompt, messages: selected)
        guard estimate <= inputTarget else { throw SidekickError.contextBudgetExceeded }

        var selectedIDs = Set(selected.map(\.id))
        for turn in turns.dropLast().reversed() {
            guard isReturnable(turn) else { continue }
            let normalized = normalize(turn, allowIncompleteCurrent: false)
            let candidate = normalized + selected
            let candidateEstimate = estimator.promptTokens(systemPrompt: systemPrompt, messages: candidate)
            guard candidateEstimate <= inputTarget else { break }
            selected = candidate
            estimate = candidateEstimate
            selectedIDs.formUnion(normalized.map(\.id))
        }

        let evicted = Set(
            turns.dropLast()
                .filter { isReturnable($0) && $0.contains(where: { !selectedIDs.contains($0.id) }) }
                .flatMap { $0.map(\.id) }
        )
        return PreparedConversation(
            systemPrompt: systemPrompt,
            conversationMessages: selected,
            estimatedPromptTokens: estimate,
            evictedMessageIDs: evicted
        )
    }

    public func prepareToolFollowUp(
        systemPrompt: String,
        messages: [ChatMessage],
        estimator: ContextEstimator
    ) throws -> PreparedConversation {
        let prepared: PreparedConversation
        do {
            prepared = try prepare(
                systemPrompt: systemPrompt,
                messages: messages,
                estimator: estimator,
                inputTarget: ContextPolicy.initialInputTarget
            )
        } catch SidekickError.contextBudgetExceeded {
            prepared = try prepare(
                systemPrompt: systemPrompt,
                messages: messages,
                estimator: estimator,
                inputTarget: ContextPolicy.totalTokenBudget - ContextPolicy.minimumFinalGenerationTokens
            )
        }
        let available = ContextPolicy.totalTokenBudget - prepared.estimatedPromptTokens
        guard available >= ContextPolicy.minimumFinalGenerationTokens else {
            throw SidekickError.contextBudgetExceeded
        }
        return prepared
    }

    private func groupTurns(_ messages: [ChatMessage]) -> [[ChatMessage]] {
        var turns: [[ChatMessage]] = []
        for message in messages {
            if message.role == .user {
                turns.append([message])
            } else if !turns.isEmpty {
                turns[turns.count - 1].append(message)
            }
        }
        return turns
    }

    private func isReturnable(_ turn: [ChatMessage]) -> Bool {
        guard turn.first?.role == .user else { return false }
        let visibleFinal = turn.last { message in
            message.role == .assistant && message.toolCalls?.isEmpty != false
        }
        guard let visibleFinal else { return false }
        return (visibleFinal.completionState ?? .complete) == .complete
    }

    private func normalize(_ turn: [ChatMessage], allowIncompleteCurrent: Bool) -> [ChatMessage] {
        if !allowIncompleteCurrent && !isReturnable(turn) { return [] }
        if allowIncompleteCurrent,
           let final = turn.last(where: { $0.role == .assistant && $0.toolCalls?.isEmpty != false }),
           (final.completionState ?? .complete) != .complete {
            return [turn[0]]
        }
        return turn.map { message in
            var normalized = message
            if message.role == .assistant && message.toolCalls?.isEmpty != false {
                normalized.reasoningContent = nil
            }
            return normalized
        }
    }
}
