# Security

Sidekick holds the user's DeepSeek and Tavily API keys, which cost money when used. It stores them in the macOS Keychain and sends them only to the service each belongs to. It sends questions, the conversation and any attached clipboard text to DeepSeek, sends search queries to Tavily, keeps the current conversation on disk for 30 minutes, and renders model output as Markdown.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately through GitHub: **Security → Report a vulnerability** on this repository ([direct link](https://github.com/nervouna/sidekick/security/advisories/new)). Include what you did, what happened, your macOS version and the release or commit you tested.

You will get an answer within a week. Fixes land on `main`; there are no maintained release branches.

## In scope

- A way for an API key to reach anything other than its own service, a log, a file or the app bundle
- A way to make Sidekick send data to a host other than DeepSeek and Tavily, or read the clipboard without the user asking
- A way for model output or search results to run code, load remote content or open a link without the user clicking it
- Conversation data kept beyond what the README describes

## Out of scope

- Anything that already needs access to the user's account, Keychain or Mac
- What DeepSeek or Tavily do with the data they receive
- Answers that are wrong or unwise but have no security effect
