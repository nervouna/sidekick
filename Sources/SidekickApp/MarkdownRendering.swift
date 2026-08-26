import SwiftUI
import MarkdownUI

enum MarkdownLinkPolicy {
    enum Disposition: Equatable {
        case systemAction
        case discarded
    }

    static func allows(_ url: URL) -> Bool {
        guard url.host != nil, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    static func disposition(for url: URL) -> Disposition {
        allows(url) ? .systemAction : .discarded
    }

    @MainActor
    static var openURLAction: OpenURLAction {
        OpenURLAction { url in
            switch disposition(for: url) {
            case .systemAction: .systemAction
            case .discarded: .discarded
            }
        }
    }
}

struct NoNetworkImageProvider: ImageProvider {
    static let placeholderText = "图片未加载"

    func makeImage(url: URL?) -> some View {
        Label(Self.placeholderText, systemImage: "photo")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }
}

struct SidekickMarkdown: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        Markdown(content)
            .markdownTheme(.sidekick)
            .markdownImageProvider(NoNetworkImageProvider())
            .environment(\.openURL, MarkdownLinkPolicy.openURLAction)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Theme {
    @MainActor
    static var sidekick: Theme { Theme.gitHub
        .text {
            ForegroundColor(.primary)
            BackgroundColor(.clear)
            FontSize(13)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            BackgroundColor(Color.secondary.opacity(0.13))
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.35))
                }
                .markdownMargin(top: 8, bottom: 6)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.2))
                }
                .markdownMargin(top: 8, bottom: 5)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.08))
                }
                .markdownMargin(top: 7, bottom: 4)
        }
        .heading4 { configuration in
            configuration.label
                .markdownTextStyle { FontWeight(.semibold) }
                .markdownMargin(top: 6, bottom: 3)
        }
        .heading5 { configuration in
            configuration.label
                .markdownTextStyle { FontWeight(.semibold) }
                .markdownMargin(top: 6, bottom: 3)
        }
        .heading6 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    ForegroundColor(.secondary)
                }
                .markdownMargin(top: 6, bottom: 3)
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.18))
                .markdownMargin(top: 0, bottom: 8)
        }
        .blockquote { configuration in
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle { ForegroundColor(.secondary) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 0, bottom: 8)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: true, vertical: true)
                    .relativeLineSpacing(.em(0.18))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.88))
                    }
                    .padding(9)
            }
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .markdownMargin(top: 0, bottom: 8)
        }
        .listItem { configuration in
            configuration.label.markdownMargin(top: .em(0.15))
        }
        .table { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: true, vertical: true)
                    .markdownTableBorderStyle(.init(color: Color.secondary.opacity(0.35)))
                    .markdownTableBackgroundStyle(
                        .alternatingRows(Color.clear, Color.secondary.opacity(0.07))
                    )
            }
            .markdownMargin(top: 0, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 { FontWeight(.semibold) }
                    BackgroundColor(nil)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 7)
        }
        .thematicBreak {
            Divider().markdownMargin(top: 8, bottom: 8)
        }
    }
}
