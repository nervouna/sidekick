import AppKit
import SwiftUI
import Testing
@testable import SidekickApp
import SidekickCore

private let markdownFixture = """
# Heading

Paragraph with **bold**, *emphasis*, ~~strike~~, [link](https://example.com), and `inline code`.

> Quote

- Item
- [x] Task

1. First

```swift
let value = 1
```

| Name | Value |
| --- | ---: |
| One | 1 |

---
"""

@Test @MainActor
func markdownFixtureAndIncompleteFenceRenderInLightAndDarkMode() {
    let contents = [markdownFixture, markdownFixture + "\n```swift\nlet unfinished ="]

    for content in contents {
        for colorScheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(
                content: SidekickMarkdown(content)
                    .frame(width: 340)
                    .padding(12)
                    .environment(\.colorScheme, colorScheme)
            )
            renderer.scale = 2
            let image = renderer.nsImage
            #expect(image != nil)
            #expect((image?.size.width ?? 0) == 364)
            #expect((image?.size.height ?? 0) > 0)
        }
    }
}

@Test
func markdownLinkPolicyOnlyAllowsAbsoluteWebURLs() {
    #expect(MarkdownLinkPolicy.allows(URL(string: "https://example.com/path")!))
    #expect(MarkdownLinkPolicy.allows(URL(string: "http://example.com")!))
    #expect(!MarkdownLinkPolicy.allows(URL(string: "file:///tmp/secret")!))
    #expect(!MarkdownLinkPolicy.allows(URL(string: "javascript:alert(1)")!))
    #expect(!MarkdownLinkPolicy.allows(URL(string: "sidekick://settings")!))
    #expect(!MarkdownLinkPolicy.allows(URL(string: "relative/path")!))
}

@Test @MainActor
func imageProviderAlwaysBuildsALocalPlaceholder() {
    let provider = NoNetworkImageProvider()
    _ = provider.makeImage(url: URL(string: "https://tracking.example/pixel.png"))
    _ = provider.makeImage(url: URL(fileURLWithPath: "/tmp/image.png"))
    #expect(NoNetworkImageProvider.placeholderText == "图片未加载")
}

@Test @MainActor
func messageBubbleUsesContentWidthUntilTheMessageNeedsToWrap() throws {
    let shortBounds = try renderedBubbleBounds(content: "好的", role: .user)
    let longBounds = try renderedBubbleBounds(
        content: String(repeating: "这是一条需要自动换行的较长消息。", count: 6),
        role: .user
    )

    #expect(shortBounds.width < 100)
    #expect(longBounds.width > 240)
    #expect(longBounds.height > shortBounds.height)
}

@MainActor
private func renderedBubbleBounds(content: String, role: MessageRole) throws -> NSRect {
    let renderer = ImageRenderer(
        content: MessageBubble(message: ChatMessage(role: role, content: content))
            .frame(width: 300)
    )
    renderer.scale = 1

    let image = try #require(renderer.nsImage)
    let data = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: data))
    var bounds = NSRect.null

    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
            bounds = bounds.union(NSRect(x: x, y: y, width: 1, height: 1))
        }
    }

    return try #require(bounds.isNull ? nil : bounds)
}

@Test @MainActor
func fullSearchConversationPopoverRendersInLightAndDarkMode() {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("session.json")
    let viewModel = ChatViewModel(sessionStore: SessionStore(fileURL: fileURL))
    let oldUser = ChatMessage(role: .user, content: "Previous question")
    let oldReply = ChatMessage(role: .assistant, content: markdownFixture)
    let currentUser = ChatMessage(role: .user, content: "Search for the latest answer")
    viewModel.session = ChatSession(messages: [oldUser, oldReply, currentUser])
    viewModel.beginActiveTimeline()
    viewModel.handle(.thinkingStarted)
    viewModel.handle(.thinkingCompleted)
    viewModel.handle(.toolCallStarted)
    viewModel.handle(.toolCallCompleted)
    viewModel.handle(.thinkingStarted)
    viewModel.handle(.thinkingCompleted)
    viewModel.handle(.finished([
        oldUser,
        oldReply,
        currentUser,
        ChatMessage(role: .assistant, content: markdownFixture)
    ]))

    for colorScheme in [ColorScheme.light, .dark] {
        let renderer = ImageRenderer(
            content: ChatView(
                viewModel: viewModel,
                onHeightChange: { _ in },
                onOpenSettings: {},
                onDismiss: {}
            )
            .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = 2
        let image = renderer.nsImage
        #expect(image?.size == NSSize(width: 400, height: 800))
    }
}

@Test @MainActor
func emptyConversationPopoverKeepsItsMinimumHeight() {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("session.json")
    let viewModel = ChatViewModel(sessionStore: SessionStore(fileURL: fileURL))
    let renderer = ImageRenderer(
        content: ChatView(
            viewModel: viewModel,
            onHeightChange: { _ in },
            onOpenSettings: {},
            onDismiss: {}
        )
    )

    renderer.scale = 2
    #expect(renderer.nsImage?.size == NSSize(width: 400, height: 400))
}
