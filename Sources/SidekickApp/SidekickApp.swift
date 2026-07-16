import AppKit
import SwiftUI
import SidekickCore

@main
struct SidekickApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var settingsController: SettingsWindowController?
    private var chatViewModel: ChatViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let keyProvider = KeyProvider()
        let viewModel = ChatViewModel(keyProvider: keyProvider)
        let settings = SettingsWindowController(keyProvider: keyProvider)
        viewModel.onOpenSettings = { [weak settings] in settings?.show() }

        chatViewModel = viewModel
        settingsController = settings
        let menuBar = MenuBarController(
            viewModel: viewModel,
            onOpenSettings: { [weak settings] in settings?.show() }
        )
        menuBarController = menuBar

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--open-on-launch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                menuBar.showPopover()
            }
        }
        #endif
    }
}
