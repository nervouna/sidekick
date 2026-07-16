import AppKit
import SwiftUI
import SidekickCore

@MainActor
final class SettingsWindowController: NSWindowController {
    init(keyProvider: KeyProvider) {
        let viewModel = SettingsViewModel(keyProvider: keyProvider)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 310),
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

    private let keyProvider: KeyProvider
    private let validator: CredentialValidator

    init(keyProvider: KeyProvider, validator: CredentialValidator = CredentialValidator()) {
        self.keyProvider = keyProvider
        self.validator = validator
        reload()
    }

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
            Spacer()
            HStack {
                Button("删除密钥", role: .destructive, action: viewModel.deleteKeys)
                Spacer()
                Button("验证连接", action: viewModel.validate).disabled(viewModel.isValidating)
                Button("保存", action: viewModel.save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 430, height: 310)
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
