import SwiftUI
import SidekickCore

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onHeightChange: (CGFloat) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversation
            Divider()
            composer
        }
        .frame(width: 400, height: viewModel.windowHeight)
        .background(Color(nsColor: .windowBackgroundColor))
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
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewModel.conversationItems.isEmpty {
                        emptyState
                    }
                    ForEach(viewModel.conversationItems) { item in
                        switch item {
                        case .message(_, let message):
                            MessageBubble(message: message)
                        case .activity(let activity):
                            ActivityRow(activity: activity)
                        case .streaming(_, let content):
                            MessageBubble(message: ChatMessage(role: .assistant, content: content))
                        }
                    }
                    if let error = viewModel.errorMessage {
                        ErrorRow(message: error, canRetry: !viewModel.session.messages.isEmpty, retry: viewModel.retry)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(14)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .onPreferenceChange(ContentHeightKey.self, perform: viewModel.updateContentHeight)
            .onChange(of: viewModel.conversationItems) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("有什么可以帮你？").font(.headline)
            Text("需要最新信息时，我会自动搜索网页。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }

    private var composer: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topLeading) {
                ComposerTextView(text: $viewModel.input, onSubmit: viewModel.send)
                    .frame(height: 64)
                if viewModel.input.isEmpty {
                    Text("向 Sidekick 提问…")
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Text("↩ 发送  ·  ⇧↩ 换行")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(action: viewModel.send) { Image(systemName: "arrow.up.circle.fill") }
                    .buttonStyle(.borderless)
                    .font(.title2)
                    .disabled(viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isGenerating)
            }
        }
        .padding(10)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 42) }
            SidekickMarkdown(message.content ?? "")
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(background, in: RoundedRectangle(cornerRadius: 12))
            if message.role == .assistant { Spacer(minLength: 30) }
        }
    }

    private var background: Color {
        message.role == .user ? Color.accentColor.opacity(0.17) : Color(nsColor: .controlBackgroundColor)
    }
}
