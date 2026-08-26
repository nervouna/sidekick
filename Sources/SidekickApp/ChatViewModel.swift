import Foundation
import SwiftUI
import SidekickCore

struct ActivityItem: Identifiable, Equatable {
    enum Kind { case thinking, search }
    let id: UUID
    let kind: Kind
    var completed: Bool

    var label: String {
        switch (kind, completed) {
        case (.thinking, false): "正在思考…"
        case (.thinking, true): "思考完成"
        case (.search, false): "正在搜索网页…"
        case (.search, true): "搜索完成"
        }
    }
}

struct ActivitySummary: Identifiable, Equatable {
    let id: UUID
    let label: String
    let completed: Bool
}

enum StreamingHeightDecision: Equatable {
    case none
    case apply(CGFloat)
    case schedule(TimeInterval)
}

struct StreamingHeightPolicy {
    static let minimumGrowth = CGFloat(40)
    static let cadence: TimeInterval = 0.3
    private static let timingTolerance: TimeInterval = 0.001

    private(set) var lastUpdateAt: Date?
    private(set) var pendingTargetHeight: CGFloat?

    mutating func observe(
        currentHeight: CGFloat,
        targetHeight: CGFloat,
        now: Date
    ) -> StreamingHeightDecision {
        guard targetHeight - currentHeight >= Self.minimumGrowth else { return .none }

        guard let lastUpdateAt else {
            self.lastUpdateAt = now
            pendingTargetHeight = nil
            return .apply(targetHeight)
        }

        let elapsed = now.timeIntervalSince(lastUpdateAt)
        guard elapsed + Self.timingTolerance < Self.cadence else {
            self.lastUpdateAt = now
            pendingTargetHeight = nil
            return .apply(targetHeight)
        }

        pendingTargetHeight = max(pendingTargetHeight ?? targetHeight, targetHeight)
        return .schedule(max(0, Self.cadence - elapsed))
    }

    mutating func flush(currentHeight: CGFloat, now: Date) -> CGFloat? {
        guard let targetHeight = pendingTargetHeight else { return nil }
        guard now.timeIntervalSince(lastUpdateAt ?? .distantPast) + Self.timingTolerance >= Self.cadence else {
            return nil
        }
        pendingTargetHeight = nil
        guard targetHeight - currentHeight >= Self.minimumGrowth else { return nil }
        lastUpdateAt = now
        return targetHeight
    }
}

enum ConversationItem: Identifiable, Equatable {
    enum ID: Hashable {
        case message(UUID)
        case activity(UUID)
        case activitySummary(UUID)
        case activeResponse(UUID)
        case contextNotice
    }

    case message(id: ID, message: ChatMessage)
    case activity(ActivityItem)
    case activitySummary(ActivitySummary)
    case streaming(id: ID, content: String)
    case contextNotice

    var id: ID {
        switch self {
        case .message(let id, _), .streaming(let id, _): id
        case .activity(let activity): .activity(activity.id)
        case .activitySummary(let summary): .activitySummary(summary.id)
        case .contextNotice: .contextNotice
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var session: ChatSession
    @Published var input = ""
    @Published var streamingContent = ""
    @Published var activities: [ActivityItem] = []
    @Published var errorMessage: String?
    @Published var isGenerating = false
    @Published var windowHeight = CGFloat(PopoverLayout.minimumHeight)
    /// Bumped whenever the composer should take focus, e.g. when the popover
    /// is summoned. The view model stays out of window management; the
    /// composer observes this counter and makes itself first responder.
    @Published private(set) var composerFocusRequest = 0
    /// Changes whenever the popover is presented so transient SwiftUI text
    /// interaction state cannot leak across popover lifetimes.
    @Published private(set) var markdownRenderGeneration = 0

    var onOpenSettings: (() -> Void)?

    private let sessionStore: any SessionStoring
    private let keyProvider: KeyProvider
    private let agent: AgentRunner
    private let dateProvider: any DateProviding
    private let contextManager: ContextManager
    private var estimator = ContextEstimator()
    private var generationTask: Task<Void, Never>?
    private var generationID = UUID()
    private(set) var activeInsertionPoint: Int?
    private var activeResponseID = UUID()
    private var activeActivitySummaryID = UUID()
    private var isStreamingResponse = false
    private var latestMeasuredWindowHeight = CGFloat(PopoverLayout.minimumHeight)
    private var streamingHeightPolicy = StreamingHeightPolicy()
    private var streamingHeightTask: Task<Void, Never>?
    private(set) var showsContextTrimNotice = false
    private var activeUserMessageID: UUID?
    private var activeTokenCount = 0

    init(
        sessionStore: any SessionStoring = SessionStore(),
        keyProvider: KeyProvider = KeyProvider(),
        agent: AgentRunner = AgentRunner(),
        dateProvider: any DateProviding = SystemDateProvider(),
        contextManager: ContextManager = ContextManager()
    ) {
        self.sessionStore = sessionStore
        self.keyProvider = keyProvider
        self.agent = agent
        self.dateProvider = dateProvider
        self.contextManager = contextManager
        do {
            session = try sessionStore.load(now: dateProvider.now())
        } catch {
            session = ChatSession(createdAt: dateProvider.now())
            errorMessage = "无法恢复上次对话：\(error.localizedDescription)"
        }
    }

    var conversationItems: [ConversationItem] {
        let messages = Self.visibleMessages(in: session.messages)
        guard let insertionPoint = activeInsertionPoint else {
            return contextNoticePrefix + messages.map { .message(id: .message($0.id), message: $0) }
        }

        let split = min(insertionPoint, messages.count)
        let prefix = messages[..<split].map { ConversationItem.message(id: .message($0.id), message: $0) }
        let suffix = messages[split...]
        let activityItems: [ConversationItem]
        if activities.count > 2 {
            activityItems = [.activitySummary(activitySummary)]
        } else {
            activityItems = activities.map(ConversationItem.activity)
        }
        var items = prefix + activityItems
        for (offset, message) in suffix.enumerated() {
            let id: ConversationItem.ID = offset == 0 ? .activeResponse(activeResponseID) : .message(message.id)
            items.append(.message(id: id, message: message))
        }
        if suffix.isEmpty, !streamingContent.isEmpty {
            items.append(.streaming(id: .activeResponse(activeResponseID), content: streamingContent))
        }
        return contextNoticePrefix + items
    }

    private var contextNoticePrefix: [ConversationItem] {
        showsContextTrimNotice ? [.contextNotice] : []
    }

    var inputCharacterCount: Int { input.count }
    var showsInputCharacterCount: Bool {
        inputCharacterCount >= ContextPolicy.characterCountDisplayThreshold
    }
    var isInputOverLimit: Bool { inputCharacterCount > ContextPolicy.userCharacterLimit }
    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isGenerating
            && !isInputOverLimit
    }

    private var activitySummary: ActivitySummary {
        let completedThinking = activities.count { $0.kind == .thinking && $0.completed }
        let completedSearch = activities.count { $0.kind == .search && $0.completed }
        var components: [String] = []
        if completedThinking > 0 { components.append("已思考 \(completedThinking) 次") }
        if completedSearch > 0 { components.append("已搜索 \(completedSearch) 次") }
        if let active = activities.last(where: { !$0.completed }) {
            components.append(active.kind == .thinking ? "正在思考…" : "正在搜索网页…")
        }
        return ActivitySummary(
            id: activeActivitySummaryID,
            label: components.joined(separator: " · "),
            completed: activities.allSatisfy(\.completed)
        )
    }

    static func visibleMessages(in messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { message in
            guard let content = message.content, !content.isEmpty else { return false }
            switch message.role {
            case .user:
                return true
            case .assistant:
                return message.toolCalls?.isEmpty != false
            case .system, .tool:
                return false
            }
        }
    }

    func requestComposerFocus() {
        composerFocusRequest += 1
    }

    func refreshForPresentation() {
        markdownRenderGeneration += 1
        guard !isGenerating else { return }
        if SessionExpiry.isExpired(session, at: dateProvider.now()) {
            newConversation()
        }
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        guard input.count <= ContextPolicy.userCharacterLimit else {
            errorMessage = SidekickError.userInputTooLong.localizedDescription
            return
        }
        refreshForPresentation()

        do {
            guard try keyProvider.key(for: .deepSeek) != nil else {
                errorMessage = SidekickError.missingKey("DeepSeek").localizedDescription
                onOpenSettings?()
                return
            }
            guard try keyProvider.key(for: .tavily) != nil else {
                errorMessage = SidekickError.missingKey("Tavily").localizedDescription
                onOpenSettings?()
                return
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let now = dateProvider.now()
        var candidate = session
        let user = ChatMessage(role: .user, content: text, createdAt: now)
        candidate.append(user, now: now)
        do {
            let prepared = try prepare(candidate.messages, at: now)
            candidate.messages = apply(prepared, to: candidate.messages)
            try sessionStore.save(candidate)
            session = candidate
            showsContextTrimNotice = showsContextTrimNotice || !prepared.evictedMessageIDs.isEmpty
            input = ""
            errorMessage = nil
            activeUserMessageID = user.id
            startGeneration(prepared: prepared)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retry() {
        guard !isGenerating,
              let userIndex = session.messages.lastIndex(where: { $0.role == .user })
        else { return }
        let final = session.messages[(userIndex + 1)...].last {
            $0.role == .assistant && $0.toolCalls?.isEmpty != false
        }
        guard final == nil || (final?.completionState ?? .complete) != .complete else { return }
        let user = session.messages[userIndex]
        var candidate = session
        candidate.messages.removeSubrange((userIndex + 1)..<candidate.messages.count)
        do {
            let prepared = try prepare(candidate.messages, at: dateProvider.now())
            candidate.messages = apply(prepared, to: candidate.messages)
            try sessionStore.save(candidate)
            session = candidate
            showsContextTrimNotice = showsContextTrimNotice || !prepared.evictedMessageIDs.isEmpty
            activeUserMessageID = user.id
            errorMessage = nil
            startGeneration(prepared: prepared)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func regenerate(replyID: UUID) {
        guard !isGenerating,
              let replyIndex = session.messages.firstIndex(where: {
                  $0.id == replyID && $0.role == .assistant && $0.toolCalls?.isEmpty != false
              }),
              let userIndex = session.messages[..<replyIndex].lastIndex(where: { $0.role == .user })
        else { return }

        do {
            guard try keyProvider.key(for: .deepSeek) != nil else {
                errorMessage = SidekickError.missingKey("DeepSeek").localizedDescription
                onOpenSettings?()
                return
            }
            guard try keyProvider.key(for: .tavily) != nil else {
                errorMessage = SidekickError.missingKey("Tavily").localizedDescription
                onOpenSettings?()
                return
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let user = session.messages[userIndex]
        var candidate = session
        candidate.messages.removeSubrange((userIndex + 1)..<candidate.messages.count)
        do {
            let prepared = try prepare(candidate.messages, at: dateProvider.now())
            candidate.messages = apply(prepared, to: candidate.messages)
            try sessionStore.save(candidate)
            session = candidate
            showsContextTrimNotice = showsContextTrimNotice || !prepared.evictedMessageIDs.isEmpty
            activeUserMessageID = user.id
            errorMessage = nil
            startGeneration(prepared: prepared)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func newConversation() {
        generationTask?.cancel()
        generationTask = nil
        generationID = UUID()
        isGenerating = false
        resetStreamingLayout()
        streamingContent = ""
        activities = []
        activeInsertionPoint = nil
        errorMessage = nil
        input = ""
        estimator = ContextEstimator()
        showsContextTrimNotice = false
        activeUserMessageID = nil
        activeTokenCount = 0
        session = ChatSession(createdAt: dateProvider.now())
        try? sessionStore.delete()
        windowHeight = CGFloat(PopoverLayout.minimumHeight)
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        generationID = UUID()
        isGenerating = false
        let endedAt = dateProvider.now()
        if !streamingContent.isEmpty {
            session.append(ChatMessage(
                role: .assistant,
                content: streamingContent,
                completionState: .cancelled,
                responseEndedAt: endedAt,
                tokenCount: activeTokenCount
            ), now: endedAt)
        } else {
            session.append(ChatMessage(
                role: .assistant,
                completionState: .cancelled,
                responseEndedAt: endedAt,
                tokenCount: activeTokenCount
            ), now: endedAt)
        }
        do {
            try sessionStore.save(session)
        } catch {
            errorMessage = "请求已取消；未能保存本次会话"
        }
        finishStreamingLayout()
        streamingContent = ""
        if errorMessage == nil { errorMessage = "请求已取消" }
    }

    func updateLayoutHeights(contentHeight: CGFloat, chromeHeight: CGFloat, now: Date? = nil) {
        let target = CGFloat(
            PopoverLayout.height(
                forContentHeight: Double(contentHeight),
                chromeHeight: Double(chromeHeight)
            )
        )
        latestMeasuredWindowHeight = target
        guard isStreamingResponse else {
            if abs(target - windowHeight) > 1 { windowHeight = target }
            return
        }

        let timestamp = now ?? dateProvider.now()
        switch streamingHeightPolicy.observe(
            currentHeight: windowHeight,
            targetHeight: target,
            now: timestamp
        ) {
        case .none:
            break
        case .apply(let height):
            streamingHeightTask?.cancel()
            streamingHeightTask = nil
            windowHeight = height
        case .schedule(let delay):
            scheduleStreamingHeightUpdate(after: delay)
        }
    }

    private func startGeneration(prepared: PreparedConversation) {
        let deepSeekKey: String
        let tavilyKey: String
        do {
            guard let deepSeek = try keyProvider.key(for: .deepSeek) else { throw SidekickError.missingKey("DeepSeek") }
            guard let tavily = try keyProvider.key(for: .tavily) else { throw SidekickError.missingKey("Tavily") }
            deepSeekKey = deepSeek
            tavilyKey = tavily
        } catch {
            errorMessage = error.localizedDescription
            onOpenSettings?()
            return
        }

        generationTask?.cancel()
        beginActiveTimeline()
        let currentID = UUID()
        generationID = currentID
        isGenerating = true
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in agent.run(
                    prepared: prepared,
                    correctionFactor: estimator.correctionFactor,
                    deepSeekKey: deepSeekKey,
                    tavilyKey: tavilyKey
                ) {
                    guard currentID == generationID else { return }
                    handle(event)
                }
            } catch {
                guard currentID == generationID else { return }
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            guard currentID == generationID else { return }
            isGenerating = false
            generationTask = nil
        }
    }

    func beginActiveTimeline() {
        resetStreamingLayout()
        activities = []
        streamingContent = ""
        activeUserMessageID = session.messages.last(where: { $0.role == .user })?.id
        activeInsertionPoint = Self.visibleMessages(in: session.messages).count
        activeResponseID = UUID()
        activeActivitySummaryID = UUID()
        activeTokenCount = 0
    }

    func handle(_ event: AgentEvent) {
        switch event {
        case .thinkingStarted:
            completeLastActivity(of: .thinking)
            activities.append(ActivityItem(id: UUID(), kind: .thinking, completed: false))
        case .thinkingCompleted:
            completeLastActivity(of: .thinking)
        case .contentDelta(let delta):
            if !isStreamingResponse {
                isStreamingResponse = true
                streamingHeightPolicy = StreamingHeightPolicy()
            }
            streamingContent += delta
        case .toolCallStarted:
            finishStreamingLayout()
            activities.append(ActivityItem(id: UUID(), kind: .search, completed: false))
        case .toolCallCompleted:
            completeLastActivity(of: .search)
            streamingContent = ""
        case .usage(let usage, let estimatedPromptTokens):
            activeTokenCount += usage.totalTokens
            estimator.observe(
                actualPromptTokens: usage.promptTokens,
                estimatedPromptTokens: estimatedPromptTokens
            )
        case .contextPrepared(let messages, let evictedMessageIDs):
            session.messages = mergeAgentMessages(messages)
            showsContextTrimNotice = showsContextTrimNotice || !evictedMessageIDs.isEmpty
            do {
                try sessionStore.save(session)
            } catch {
                errorMessage = "对话仍在继续，但暂时无法保存本次会话"
            }
        case .finished(let messages):
            finishStreamingLayout()
            session.messages = mergeAgentMessages(messages)
            let endedAt = dateProvider.now()
            stampActiveResponse(endedAt: endedAt)
            session.lastMessageAt = endedAt
            streamingContent = ""
            var didSave = true
            do {
                try sessionStore.save(session)
            } catch {
                didSave = false
                errorMessage = "回答已生成，但无法保存本次会话"
            }
            if didSave,
               let final = session.messages.last,
               final.role == .assistant,
               final.completionState == .truncated {
                errorMessage = "回答达到长度上限，请缩小问题后重试"
            }
        case .failed(let message, let messages):
            finishStreamingLayout()
            if let messages {
                session.messages = mergeAgentMessages(messages)
                let endedAt = dateProvider.now()
                stampActiveResponse(endedAt: endedAt)
                session.lastMessageAt = endedAt
                do {
                    try sessionStore.save(session)
                } catch {
                    errorMessage = "\(message)；回答已显示，但无法保存本次会话"
                    streamingContent = ""
                    return
                }
            }
            streamingContent = ""
            errorMessage = message
        }
    }

    private func stampActiveResponse(endedAt: Date) {
        guard let activeUserMessageID,
              let userIndex = session.messages.firstIndex(where: { $0.id == activeUserMessageID }),
              let replyIndex = session.messages.indices.reversed().first(where: { index in
                  index > userIndex
                      && session.messages[index].role == .assistant
                      && session.messages[index].toolCalls?.isEmpty != false
              })
        else { return }
        session.messages[replyIndex].responseEndedAt = endedAt
        session.messages[replyIndex].tokenCount = activeTokenCount
    }

    private func prepare(_ messages: [ChatMessage], at date: Date) throws -> PreparedConversation {
        let prompt = SidekickSystemPrompt.render(context: SystemPromptContext(
            date: date,
            timeZone: .current,
            locale: .current
        ))
        return try contextManager.prepare(
            systemPrompt: prompt,
            messages: messages,
            estimator: estimator
        )
    }

    private func apply(_ prepared: PreparedConversation, to messages: [ChatMessage]) -> [ChatMessage] {
        let normalized = Dictionary(uniqueKeysWithValues: prepared.conversationMessages.map { ($0.id, $0) })
        return messages.compactMap { message in
            guard !prepared.evictedMessageIDs.contains(message.id) else { return nil }
            return normalized[message.id] ?? message
        }
    }

    private func mergeAgentMessages(_ agentMessages: [ChatMessage]) -> [ChatMessage] {
        guard let activeUserMessageID,
              let sessionUserIndex = session.messages.firstIndex(where: { $0.id == activeUserMessageID }),
              let agentUserIndex = agentMessages.firstIndex(where: { $0.id == activeUserMessageID })
        else { return agentMessages }

        let returnedIDs = Set(agentMessages[..<agentUserIndex].map(\.id))
        let prefix = Array(session.messages[..<sessionUserIndex])
        var preserved: [ChatMessage] = []
        var turn: [ChatMessage] = []
        func appendTurn(_ candidate: [ChatMessage], to output: inout [ChatMessage]) {
            guard !candidate.isEmpty else { return }
            let final = candidate.last { $0.role == .assistant && $0.toolCalls?.isEmpty != false }
            let incomplete = final.map { ($0.completionState ?? .complete) != .complete } ?? true
            if incomplete {
                output.append(contentsOf: candidate)
            } else {
                output.append(contentsOf: candidate.filter { returnedIDs.contains($0.id) })
            }
        }
        for message in prefix {
            if message.role == .user {
                appendTurn(turn, to: &preserved)
                turn = [message]
            } else {
                turn.append(message)
            }
        }
        appendTurn(turn, to: &preserved)
        preserved.append(contentsOf: agentMessages[agentUserIndex...])
        return preserved
    }

    private func completeLastActivity(of kind: ActivityItem.Kind) {
        guard let index = activities.lastIndex(where: { $0.kind == kind && !$0.completed }) else { return }
        activities[index].completed = true
    }

    private func scheduleStreamingHeightUpdate(after delay: TimeInterval) {
        guard streamingHeightTask == nil else { return }
        streamingHeightTask = Task { [weak self] in
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            streamingHeightTask = nil
            guard isStreamingResponse else { return }
            if let height = streamingHeightPolicy.flush(
                currentHeight: windowHeight,
                now: dateProvider.now()
            ) {
                windowHeight = height
            }
        }
    }

    private func finishStreamingLayout() {
        guard isStreamingResponse else { return }
        streamingHeightTask?.cancel()
        streamingHeightTask = nil
        streamingHeightPolicy = StreamingHeightPolicy()
        isStreamingResponse = false
        if abs(latestMeasuredWindowHeight - windowHeight) > 1 {
            windowHeight = latestMeasuredWindowHeight
        }
    }

    private func resetStreamingLayout() {
        streamingHeightTask?.cancel()
        streamingHeightTask = nil
        streamingHeightPolicy = StreamingHeightPolicy()
        isStreamingResponse = false
    }
}
