# Sidekick

Sidekick 是一个原生 macOS 菜单栏 AI 对话 App。它使用 DeepSeek V4 Flash 流式回答，并在需要最新信息时通过 Tavily 自动搜索网页。

## 下载

[下载最新 macOS 版本](https://github.com/nervouna/sidekick/releases/latest/download/Sidekick-macOS-arm64.zip)

公开下载包适用于 Apple Silicon Mac，已使用 Developer ID Application 签名并通过 Apple 公证。安装后请在设置中填写 DeepSeek 与 Tavily API Key。

## 要求

- macOS 14 或更高版本
- Xcode 16 / Swift 6 或更高版本
- DeepSeek 与 Tavily API Key

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

## 使用

- 单击菜单栏闪光图标打开对话，或按全局快捷键 `⌥Space` 随时唤出与收起；弹窗打开时光标已在输入框，可直接输入。
- `Esc` 收起弹窗。使用输入法时，第一次 `Esc` 先关闭候选框。
- 可在设置页点按快捷键框后按下新的组合键来重新绑定；按 `Delete` 恢复默认。快捷键需要包含 `⌃`、`⌥` 或 `⌘` 之一，功能键可单独使用。
- 若按下快捷键没有反应，通常是被其他 App 占用，换一个组合键即可。
- `Return` 发送，`Shift+Return` 换行。
- 单条用户输入最多 1000 个字符；超过上限时会保留全文供继续编辑，但不能发送。
- 用户消息、助手回复和流式内容支持 Markdown 排版。
- 右键菜单栏图标可打开设置或退出 App。
- 当前会话是 30 分钟有效的临时上下文，会在下次打开弹窗或发送前惰性清空。
- 为控制成本、延迟和隐私，较早的完整问答可能被自动移除；界面会明确提示，移除内容也会同步从临时会话文件删除。
- 已取消、达到长度上限、被过滤或意外中断的回答仍可显示，但不会参与后续上下文；可以使用“重试”替换该次不完整回答。
- Sidekick 不提供长期记忆、历史检索或跨会话召回。
