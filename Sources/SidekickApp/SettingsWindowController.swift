import AppKit
import SwiftUI
import SidekickCore

@MainActor
final class SettingsWindowController: NSWindowController {
    init(
        keyProvider: KeyProvider,
        hotKeyStore: any HotKeyStoring,
        initialHotKeyStatus: String,
        onRebindHotKey: @escaping (HotKeyBinding) throws -> Void
    ) {
        let viewModel = SettingsViewModel(
            keyProvider: keyProvider,
            hotKeyStore: hotKeyStore,
            initialHotKeyStatus: initialHotKeyStatus,
            onRebindHotKey: onRebindHotKey
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sidekick 设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: SettingsView(viewModel: viewModel))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var deepSeekKey = ""
    @Published var tavilyKey = ""
    @Published var status = ""
    @Published var isValidating = false
    @Published var deepSeekFromEnvironment = false
    @Published var tavilyFromEnvironment = false
    @Published private(set) var hotKey: HotKeyBinding
    @Published private(set) var hotKeyStatus: String

    private let keyProvider: KeyProvider
    private let validator: CredentialValidator
    private let hotKeyStore: any HotKeyStoring
    private let onRebindHotKey: (HotKeyBinding) throws -> Void

    init(
        keyProvider: KeyProvider,
        validator: CredentialValidator = CredentialValidator(),
        hotKeyStore: any HotKeyStoring,
        initialHotKeyStatus: String,
        onRebindHotKey: @escaping (HotKeyBinding) throws -> Void
    ) {
        self.keyProvider = keyProvider
        self.validator = validator
        self.hotKeyStore = hotKeyStore
        self.onRebindHotKey = onRebindHotKey
        hotKey = hotKeyStore.load()
        hotKeyStatus = initialHotKeyStatus
        reload()
    }

    func applyHotKey(_ binding: HotKeyBinding) {
        guard binding != hotKey else { return }
        guard binding.isValid else {
            hotKeyStatus = HotKeyError.invalidBinding.localizedDescription
            return
        }
        do {
            try onRebindHotKey(binding)
            hotKeyStore.save(binding)
            hotKey = binding
            // Carbon returns noErr even for chords another app already owns
            // (⌘Space registers fine and simply never fires), so this can
            // only claim the binding was set, not that it will work.
            hotKeyStatus = "已设置 \(binding.displayString)；若按下无响应，说明已被其他 App 占用，请换一个组合键。"
        } catch {
            hotKeyStatus = error.localizedDescription
            // Registering a new chord tears the old one down first, so restore
            // it rather than leaving the user with no shortcut at all.
            try? onRebindHotKey(hotKey)
        }
    }

    func resetHotKey() { applyHotKey(.default) }

    func reload() {
        do {
            deepSeekKey = try keyProvider.keychainValue(for: .deepSeek) ?? ""
            tavilyKey = try keyProvider.keychainValue(for: .tavily) ?? ""
            let resolvedDeepSeek = try keyProvider.key(for: .deepSeek)
            let resolvedTavily = try keyProvider.key(for: .tavily)
            deepSeekFromEnvironment = deepSeekKey.isEmpty && resolvedDeepSeek != nil
            tavilyFromEnvironment = tavilyKey.isEmpty && resolvedTavily != nil
        } catch { status = error.localizedDescription }
    }

    func save() {
        do {
            try keyProvider.save(deepSeekKey, for: .deepSeek)
            try keyProvider.save(tavilyKey, for: .tavily)
            status = "已安全保存到 macOS 钥匙串"
            reload()
        } catch { status = error.localizedDescription }
    }

    func deleteKeys() {
        do {
            try keyProvider.delete(.deepSeek)
            try keyProvider.delete(.tavily)
            deepSeekKey = ""
            tavilyKey = ""
            status = "已删除钥匙串中的密钥"
            reload()
        } catch { status = error.localizedDescription }
    }

    func validate() {
        save()
        isValidating = true
        status = "正在验证…"
        Task {
            do {
                guard let deepSeek = try keyProvider.key(for: .deepSeek) else { throw SidekickError.missingKey("DeepSeek") }
                guard let tavily = try keyProvider.key(for: .tavily) else { throw SidekickError.missingKey("Tavily") }
                try await validator.validate(deepSeek, for: .deepSeek)
                try await validator.validate(tavily, for: .tavily)
                status = "DeepSeek 与 Tavily 均连接成功"
            } catch { status = error.localizedDescription }
            isValidating = false
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Keys").font(.title2.bold())
            keyField("DeepSeek", text: $viewModel.deepSeekKey, environment: viewModel.deepSeekFromEnvironment)
            keyField("Tavily", text: $viewModel.tavilyKey, environment: viewModel.tavilyFromEnvironment)
            if !viewModel.status.isEmpty {
                Text(viewModel.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Divider()
            hotKeySection
            Spacer()
            HStack {
                Button("删除密钥", role: .destructive, action: viewModel.deleteKeys)
                Spacer()
                Button("验证连接", action: viewModel.validate).disabled(viewModel.isValidating)
                Button("保存", action: viewModel.save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 430, height: 400)
    }

    private var hotKeySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("全局快捷键").font(.title2.bold())
            HStack(spacing: 10) {
                ShortcutRecorder(binding: viewModel.hotKey, onRecord: viewModel.applyHotKey)
                    .frame(height: 26)
                Button("恢复默认", action: viewModel.resetHotKey)
            }
            Text(viewModel.hotKeyStatus.isEmpty
                 ? "点按后按下想用的组合键，可随时唤出或收起对话。"
                 : viewModel.hotKeyStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func keyField(_ title: String, text: Binding<String>, environment: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.headline)
                if environment { Text("使用 Debug 环境变量").font(.caption).foregroundStyle(.secondary) }
            }
            SecureField("输入 \(title) API Key", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
