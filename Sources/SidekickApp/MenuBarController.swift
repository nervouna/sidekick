import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let viewModel: ChatViewModel
    private let onOpenSettings: () -> Void
    private let contextMenu = NSMenu()

    init(viewModel: ChatViewModel, onOpenSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Sidekick")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        contextMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        contextMenu.addItem(.separator())
        contextMenu.addItem(withTitle: "退出 Sidekick", action: #selector(quit), keyEquivalent: "q").target = self

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 400, height: 400)
        popover.contentViewController = NSHostingController(
            rootView: ChatView(
                viewModel: viewModel,
                onHeightChange: { [weak self] height in
                    self?.popover.contentSize = NSSize(width: 400, height: height)
                },
                onOpenSettings: onOpenSettings
            )
        )
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        viewModel.refreshForPresentation()
        guard let button = statusItem.button else { return }
        popover.contentSize = NSSize(width: 400, height: viewModel.windowHeight)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        viewModel.refreshForPresentation()
        popover.contentSize = NSSize(width: 400, height: viewModel.windowHeight)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettings() { onOpenSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
