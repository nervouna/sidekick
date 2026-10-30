# Sidekick

[English](README.md) | 简体中文

[![Verify](https://github.com/nervouna/sidekick/actions/workflows/verify.yml/badge.svg)](https://github.com/nervouna/sidekick/actions/workflows/verify.yml)
[![Release](https://img.shields.io/github/v/release/nervouna/sidekick)](https://github.com/nervouna/sidekick/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

<!-- banner -->

Sidekick 是一个原生 macOS 菜单栏 AI 对话 App。它使用 DeepSeek V4 Flash 流式回答，并在需要最新信息时通过 Tavily 自动搜索网页。

<!-- screenshots -->

## 状态

Sidekick 是个人项目，当前版本 0.1。运行需要 macOS 14 或更高版本的 Apple Silicon Mac，以及你自己的 DeepSeek 与 Tavily API Key；token 费用由 DeepSeek 计费，搜索由 Tavily 计费。界面为简体中文，回答使用提问所用的语言。GitHub Releases 中的版本使用 Developer ID 签名并经过 Apple 公证，最新版本为 v0.1.0。

## 开发方式

大部分代码由编程代理编写。`AGENTS.md` 是它们遵循的规则：确认的改动直接提交并推送到 `main`，不经过 pull request 审核；交给人验收的构建必须使用 Developer ID 签名，不能是临时签名；公开发布通过 `.agents/skills/release-sidekick-macos` 中的发布流程完成公证。每次推送到 `main` 时，CI 运行单元测试和发布脚本的 dry run。报告 bug 或提交修复见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全问题见 [SECURITY.md](SECURITY.md)。

## 下载

[下载最新 macOS 版本](https://github.com/nervouna/sidekick/releases/latest/download/Sidekick-macOS-arm64.zip)

公开下载包适用于 Apple Silicon Mac，已使用 Developer ID Application 签名并通过 Apple 公证。安装后请在设置中填写 DeepSeek 与 Tavily API Key。

## 要求

- macOS 14 或更高版本
- Xcode 16 / Swift 6 或更高版本
- DeepSeek 与 Tavily API Key

## 使用

- 单击菜单栏闪光图标打开对话，或按全局快捷键 `⌥Space` 随时唤出与收起；弹窗打开时光标已在输入框，可直接输入。
- `Esc` 收起弹窗。使用输入法时，第一次 `Esc` 先关闭候选框。
- 可在设置页点按快捷键框后按下新的组合键来重新绑定；按 `Delete` 恢复默认。快捷键需要包含 `⌃`、`⌥` 或 `⌘` 之一，功能键可单独使用。
- 若按下快捷键没有反应，通常是被其他 App 占用，换一个组合键即可。
- `Return` 发送，`Shift+Return` 换行。
- 单条用户输入最多 1000 个字符；超过上限时会保留全文供继续编辑，但不能发送。
- 点击“使用剪贴板”可把剪贴板文本附带到下一个问题，最多 4000 字；点击“移除”取消附带。
- 用户消息、助手回复和流式内容支持 Markdown 排版。
- 右键菜单栏图标可打开设置或退出 App。
- 当前会话是 30 分钟有效的临时上下文，会在下次打开弹窗或发送前惰性清空。
- 为控制成本、延迟和隐私，较早的完整问答可能被自动移除；界面会明确提示，移除内容也会同步从临时会话文件删除。
- 已取消、达到长度上限、被过滤或意外中断的回答仍可显示，但不会参与后续上下文；可以使用“重试”替换该次不完整回答。
- Sidekick 不提供长期记忆、历史检索或跨会话召回。

## 密钥、数据与网络

- 设置页填写的 API Key 保存在 macOS 钥匙串（服务 `io.damao.sidekick`，账户 `deepseek` 和 `tavily`），优先于环境变量 `DEEPSEEK_API_KEY` 和 `TAVILY_API_KEY`。设置页的“删除密钥”会从钥匙串删除它们。
- **DeepSeek**（`api.deepseek.com`）收到每个问题及当前会话、附带的剪贴板文本、该问题的搜索结果，以及包含本地日期时间、时区和区域设置的系统提示词。
- **Tavily**（`api.tavily.com`）收到模型生成的搜索词，每个问题最多两次。你的消息本身不会发给 Tavily。
- 设置页的“验证连接”会把每个 Key 发给对应服务进行校验。
- **本机存储**：当前会话在 30 分钟内保存在 `~/Library/Application Support/Sidekick/current-session.json`；快捷键保存在 App 的 user defaults（`io.damao.sidekick`）。
- 只有点击“使用剪贴板”时才读取剪贴板。
- 回答中的图片显示为占位符，不从网络加载。
- Sidekick 不发送其他内容，也没有统计分析。

## 卸载

1. 在设置页关闭“登录时打开”，并点击“删除密钥”。
2. 右键菜单栏图标，选择“退出 Sidekick”，然后将 `Sidekick.app` 移到废纸篓。
3. 如需删除其余数据：

   ```sh
   rm -rf ~/Library/Application\ Support/Sidekick
   defaults delete io.damao.sidekick
   ```

## 本地调试

项目根目录的 `.env` 使用以下变量名：

```dotenv
DEEPSEEK_API_KEY=...
TAVILY_API_KEY=...
```

`.env` 已被 Git 忽略，也不会进入 App Bundle。启动调试版本：

```sh
./scripts/run_debug.sh
```

UI 自动验收时可让调试版启动后直接展开弹窗：`Sidekick --open-on-launch`。该参数只在 Debug 构建中生效。

也可以在 App 的设置页填写 Key；设置页中的值保存在 macOS 钥匙串，并优先于环境变量。

## 构建与验证

```sh
./scripts/build_app.sh
./scripts/verify.sh
```

如需使用 `.env` 做最小真实 API 连通性测试（会消耗少量 DeepSeek tokens 和 1 次 Tavily Search credit）：

```sh
./scripts/smoke_api.sh
```

修改系统提示词后，可显式运行真实模型行为评测。该命令复用 `.env` 中的 `DEEPSEEK_API_KEY`，会消耗少量 DeepSeek tokens，但使用固定搜索结果，不消耗 Tavily Search credit，也不属于默认 `verify.sh`：

```sh
./scripts/eval_prompt.sh
```

生成的本地调试 App 位于 `build/Sidekick.app`。它采用本机临时签名，仅用于开发与个人调试，不应作为公开发布产物；面向用户的已签名、公证版本由 GitHub Releases 提供。

## 许可证

MIT，见 [LICENSE](LICENSE)。
