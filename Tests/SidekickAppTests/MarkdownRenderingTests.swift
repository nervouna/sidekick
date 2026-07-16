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
                onOpenSettings: {}
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
            onOpenSettings: {}
        )
    )

    renderer.scale = 2
    #expect(renderer.nsImage?.size == NSSize(width: 400, height: 400))
}
