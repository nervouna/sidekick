# Sidekick

Sidekick 是一个原生 macOS 菜单栏 AI 对话 App。它使用 DeepSeek V4 Flash 流式回答，并在需要最新信息时通过 Tavily 自动搜索网页。

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

生成的本地调试 App 位于 `build/Sidekick.app`。它采用本机临时签名，仅用于开发与个人调试，尚未包含 Developer ID 签名、公证或发布流程。

## 使用

- 单击菜单栏闪光图标打开对话。
- `Return` 发送，`Shift+Return` 换行。
- 右键菜单栏图标可打开设置或退出 App。
- 60 分钟无新消息后，当前会话会在下次打开或发送时清空。
