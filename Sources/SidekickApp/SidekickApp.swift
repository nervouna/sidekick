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
    private var hotKeyMonitor: GlobalHotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let keyProvider = KeyProvider()
        let viewModel = ChatViewModel(keyProvider: keyProvider)
        chatViewModel = viewModel

        let menuBar = MenuBarController(
            viewModel: viewModel,
            onOpenSettings: { [weak self] in self?.settingsController?.show() }
        )
        menuBarController = menuBar

        let monitor = GlobalHotKeyMonitor { [weak menuBar] in menuBar?.toggle() }
        hotKeyMonitor = monitor
        let hotKeyStore = UserDefaultsHotKeyStore()
        let storedHotKey = hotKeyStore.load()
        // A failed registration at launch is reported in Settings rather than
        // interrupting startup — the menu bar icon still works either way.
        var hotKeyStatus = ""
        do {
            try monitor.register(storedHotKey)
        } catch {
            hotKeyStatus = error.localizedDescription
        }

        let settings = SettingsWindowController(
            keyProvider: keyProvider,
            hotKeyStore: hotKeyStore,
            initialHotKeyStatus: hotKeyStatus,
            onRebindHotKey: { [weak monitor] binding in
                guard let monitor else { return }
                try monitor.register(binding)
            }
        )
        settingsController = settings
        viewModel.onOpenSettings = { [weak settings] in settings?.show() }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--open-on-launch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                menuBar.showPopover()
            }
        }
        #endif
    }
}
