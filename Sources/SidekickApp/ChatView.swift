import AppKit
import SwiftUI
import SidekickCore

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onHeightChange: (CGFloat) -> Void
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header.measuringHeight(as: .header)
            Divider()
            conversation
            Divider()
            composer.measuringHeight(as: .composer)
        }
        .frame(width: CGFloat(PopoverLayout.width), height: viewModel.windowHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .onPreferenceChange(LayoutHeightKey.self) { heights in
            guard let contentHeight = heights[.content],
                  let headerHeight = heights[.header],
                  let composerHeight = heights[.composer]
            else { return }
            viewModel.updateLayoutHeights(
                contentHeight: contentHeight,
                chromeHeight: headerHeight + composerHeight
            )
        }
        .onChange(of: viewModel.windowHeight) { _, height in onHeightChange(height) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.tint)
            Text("Sidekick").font(.headline)
            Spacer()
            if viewModel.isGenerating {
                Button(action: viewModel.cancelGeneration) {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .help("停止生成")
            }
            Button(action: viewModel.newConversation) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("新对话")
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("设置")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.conversationItems.isEmpty {
                        emptyState
                    }
                    ForEach(viewModel.conversationItems) { item in
                        switch item {
                        case .message(_, let message):
                            MessageBubble(
                                message: message,
                                markdownRenderGeneration: viewModel.markdownRenderGeneration,
                                canRegenerate: !viewModel.isGenerating,
                                onCopy: { copyMarkdown(message.content ?? "") },
                                onRegenerate: { viewModel.regenerate(replyID: message.id) }
                            )
                        case .activity(let activity):
                            ActivityRow(activity: activity)
                        case .activitySummary(let summary):
                            ActivitySummaryRow(summary: summary)
                        case .streaming(_, let content):
                            MessageBubble(
                                message: ChatMessage(role: .assistant, content: content),
                                markdownRenderGeneration: viewModel.markdownRenderGeneration,
                                showsResponseMetadata: false
                            )
                        case .contextNotice:
                            ContextNoticeRow()
                        }
                    }
                    if let error = viewModel.errorMessage {
                        ErrorRow(message: error, canRetry: !viewModel.session.messages.isEmpty, retry: viewModel.retry)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(14)
                .measuringHeight(as: .content)
            }
            .onChange(of: viewModel.conversationItems.map(\.id)) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: viewModel.streamingContent) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("有什么可以帮你？").font(.headline)
            Text("按全局快捷键或点菜单栏图标即可唤出。需要最新信息时可在设置中填写 Tavily。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }

    private var composer: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topLeading) {
                ComposerTextView(
                    text: $viewModel.input,
                    focusRequest: viewModel.composerFocusRequest,
                    onSubmit: viewModel.send,
                    onDismiss: onDismiss
                )
                .frame(height: 64)
                if viewModel.input.isEmpty {
                    Text("向 Sidekick 提问…")
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
            if let attached = viewModel.attachedContext {
                HStack(spacing: 6) {
                    Label("已附带剪贴板文本，\(attached.count) 字", systemImage: "doc.on.clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("移除", action: viewModel.clearAttachedContext)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            HStack {
                Text("↩ 发送  ·  ⇧↩ 换行")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("使用剪贴板", action: viewModel.attachClipboardContext)
                    .buttonStyle(.link)
                    .font(.caption)
                    .disabled(viewModel.isGenerating)
                Spacer()
                if viewModel.showsInputCharacterCount {
                    Text("\(viewModel.inputCharacterCount) / \(ContextPolicy.userCharacterLimit)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(viewModel.isInputOverLimit ? .red : .secondary)
                        .accessibilityLabel("已输入 \(viewModel.inputCharacterCount) 个字符，上限 \(ContextPolicy.userCharacterLimit) 个字符")
                }
                Button(action: viewModel.send) { Image(systemName: "arrow.up.circle.fill") }
                    .buttonStyle(.borderless)
                    .font(.title2)
                    .disabled(!viewModel.canSend)
            }
            if viewModel.isInputOverLimit {
                Text("问题不能超过 1000 个字符，请删减后发送。")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
    }
}

private enum LayoutComponent: Hashable {
    case header
    case content
    case composer
}

private struct LayoutHeightKey: PreferenceKey {
    static let defaultValue: [LayoutComponent: CGFloat] = [:]

    static func reduce(value: inout [LayoutComponent: CGFloat], nextValue: () -> [LayoutComponent: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private extension View {
    func measuringHeight(as component: LayoutComponent) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: LayoutHeightKey.self, value: [component: proxy.size.height])
            }
        }
    }
}

private struct ActivityRow: View {
    let activity: ActivityItem
    var body: some View {
        Label(activity.label, systemImage: activity.kind == .thinking ? "brain.head.profile" : "globe")
            .font(.caption)
            .foregroundStyle(.secondary)
            .symbolEffect(.pulse, isActive: !activity.completed)
    }
}

private struct ActivitySummaryRow: View {
    let summary: ActivitySummary

    var body: some View {
        Label(summary.label, systemImage: "sparkles")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel(summary.label)
            .symbolEffect(.pulse, isActive: !summary.completed)
    }
}

private struct ErrorRow: View {
    let message: String
    let canRetry: Bool
    let retry: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).textSelection(.enabled)
            Spacer()
            if canRetry { Button("重试", action: retry).buttonStyle(.link) }
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ContextNoticeRow: View {
    var body: some View {
        Label("为保持对话轻量，已移除较早内容。", systemImage: "text.badge.minus")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var markdownRenderGeneration = 0
    var showsResponseMetadata = true
    var canRegenerate = true
    var onCopy: () -> Void = {}
    var onRegenerate: () -> Void = {}

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 42) }
            ViewThatFits(in: .horizontal) {
                messageContent.fixedSize(horizontal: true, vertical: false)
                messageContent
            }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(background, in: RoundedRectangle(cornerRadius: 12))
            if message.role == .assistant { Spacer(minLength: 30) }
        }
    }

    private var background: Color {
        message.role == .user ? Color.accentColor.opacity(0.17) : Color(nsColor: .controlBackgroundColor)
    }

    private var messageContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            SidekickMarkdown(message.content ?? "")
                .id(markdownRenderGeneration)
            if message.role == .user, let attached = message.attachedContext, !attached.isEmpty {
                Text("已附带剪贴板文本，\(attached.count) 字")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if message.role == .assistant && showsResponseMetadata {
                ResponseMetadataRow(
                    endedAt: message.responseEndedAt ?? message.createdAt,
                    tokenCount: message.tokenCount,
                    canRegenerate: canRegenerate,
                    onCopy: onCopy,
                    onRegenerate: onRegenerate
                )
            }
            if let label = completionLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var completionLabel: String? {
        switch message.completionState {
        case .cancelled: "已取消，未用于后续上下文"
        case .truncated: "回答已截断，未用于后续上下文"
        case .filtered: "回答受安全策略限制，未用于后续上下文"
        case .interrupted: "回答已中断，未用于后续上下文"
        case .complete, .none: nil
        }
    }
}

private struct ResponseMetadataRow: View {
    let endedAt: Date
    let tokenCount: Int?
    let canRegenerate: Bool
    let onCopy: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            metadataButton(
                systemName: "doc.on.doc",
                label: "复制 Markdown",
                action: onCopy
            )
            metadataButton(
                systemName: "arrow.clockwise",
                label: "重新生成回复",
                action: onRegenerate
            )
            .disabled(!canRegenerate)
            Text(ResponseMetadataFormatter.timestamp(endedAt))
            Text(tokenCount.map(ResponseMetadataFormatter.tokens) ?? "-- tokens")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .contain)
    }

    private func metadataButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
                .frame(minWidth: 14, minHeight: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
        .help(label)
    }
}

enum ResponseMetadataFormatter {
    static func timestamp(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed >= 0, elapsed < 60 * 60 {
            let minutes = Int(elapsed / 60)
            return minutes == 0 ? "刚刚" : "\(minutes) 分钟前"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now)
            ? "HH:mm"
            : "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func tokens(_ count: Int) -> String {
        let nonnegativeCount = max(0, count)
        if nonnegativeCount >= 1_000_000 {
            return "\(rounded(nonnegativeCount, divisor: 1_000_000))M tokens"
        }
        if nonnegativeCount >= 10_000 {
            return "\(rounded(nonnegativeCount, divisor: 1_000))K tokens"
        }
        return "\(nonnegativeCount.formatted(.number.grouping(.automatic))) tokens"
    }

    private static func rounded(_ count: Int, divisor: Int) -> Int {
        (count + divisor / 2) / divisor
    }
}

private func copyMarkdown(_ markdown: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(markdown, forType: .string)
}
