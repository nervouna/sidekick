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
    }

    case message(id: ID, message: ChatMessage)
    case activity(ActivityItem)
    case activitySummary(ActivitySummary)
    case streaming(id: ID, content: String)

    var id: ID {
        switch self {
        case .message(let id, _), .streaming(let id, _): id
        case .activity(let activity): .activity(activity.id)
        case .activitySummary(let summary): .activitySummary(summary.id)
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

    var onOpenSettings: (() -> Void)?

    private let sessionStore: SessionStore
    private let keyProvider: KeyProvider
    private let agent: AgentRunner
    private let dateProvider: any DateProviding
    private var generationTask: Task<Void, Never>?
    private var generationID = UUID()
    private(set) var activeInsertionPoint: Int?
    private var activeResponseID = UUID()
    private var activeActivitySummaryID = UUID()
    private var isStreamingResponse = false
    private var latestMeasuredWindowHeight = CGFloat(PopoverLayout.minimumHeight)
    private var streamingHeightPolicy = StreamingHeightPolicy()
    private var streamingHeightTask: Task<Void, Never>?

    init(
        sessionStore: SessionStore = SessionStore(),
        keyProvider: KeyProvider = KeyProvider(),
        agent: AgentRunner = AgentRunner(),
        dateProvider: any DateProviding = SystemDateProvider()
    ) {
        self.sessionStore = sessionStore
        self.keyProvider = keyProvider
        self.agent = agent
        self.dateProvider = dateProvider
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
            return messages.map { .message(id: .message($0.id), message: $0) }
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
        return items
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

    func refreshForPresentation() {
        guard !isGenerating else { return }
        if SessionExpiry.isExpired(session, at: dateProvider.now()) {
            newConversation()
        }
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
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

        input = ""
        errorMessage = nil
        session.append(ChatMessage(role: .user, content: text), now: dateProvider.now())
        try? sessionStore.save(session)
        startGeneration()
    }

    func retry() {
        guard !isGenerating, session.messages.last(where: { $0.role == .user }) != nil else { return }
        errorMessage = nil
        startGeneration()
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
        session = ChatSession(createdAt: dateProvider.now())
        try? sessionStore.delete()
        windowHeight = CGFloat(PopoverLayout.minimumHeight)
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        generationID = UUID()
        isGenerating = false
        if !streamingContent.isEmpty {
            session.append(ChatMessage(role: .assistant, content: streamingContent), now: dateProvider.now())
            try? sessionStore.save(session)
        }
        finishStreamingLayout()
        streamingContent = ""
        errorMessage = "请求已取消"
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

    private func startGeneration() {
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
        let startingMessages = session.messages

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in agent.run(
                    messages: startingMessages,
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
        activeInsertionPoint = Self.visibleMessages(in: session.messages).count
        activeResponseID = UUID()
        activeActivitySummaryID = UUID()
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
        case .finished(let messages):
            finishStreamingLayout()
            session.messages = messages
            session.lastMessageAt = dateProvider.now()
            streamingContent = ""
            try? sessionStore.save(session)
        case .failed(let message):
            finishStreamingLayout()
            errorMessage = message
        }
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
