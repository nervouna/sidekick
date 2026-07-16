#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
set -a
source "$ROOT/.env"
set +a

: "${DEEPSEEK_API_KEY:?DEEPSEEK_API_KEY is missing}"
: "${TAVILY_API_KEY:?TAVILY_API_KEY is missing}"

DEEPSEEK_RESPONSE="$(mktemp -t sidekick-deepseek)"
TAVILY_RESPONSE="$(mktemp -t sidekick-tavily)"
trap 'rm -f "$DEEPSEEK_RESPONSE" "$TAVILY_RESPONSE"' EXIT

DEEPSEEK_STATUS="$(curl --silent --show-error \
  --output "$DEEPSEEK_RESPONSE" \
  --write-out '%{http_code}' \
  https://api.deepseek.com/v1/chat/completions \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
  -H 'Content-Type: application/json' \
  --data '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"Reply with OK."}],"stream":true,"thinking":{"type":"enabled"},"reasoning_effort":"high","max_tokens":32,"tools":[{"type":"function","function":{"name":"web_search","description":"Search the web","parameters":{"type":"object","properties":{"query":{"type":"string"}},"required":["query"],"additionalProperties":false}}}]}')"

if [[ "$DEEPSEEK_STATUS" != "200" ]] || ! grep -q 'data: \[DONE\]' "$DEEPSEEK_RESPONSE"; then
  print -u2 -- "DeepSeek smoke test failed (HTTP $DEEPSEEK_STATUS)"
  exit 1
fi
print -r -- "DeepSeek streaming: OK (HTTP 200)"

TAVILY_STATUS="$(curl --silent --show-error \
  --output "$TAVILY_RESPONSE" \
  --write-out '%{http_code}' \
  https://api.tavily.com/search \
  -H "Authorization: Bearer $TAVILY_API_KEY" \
  -H 'Content-Type: application/json' \
  --data '{"query":"OpenAI official website","search_depth":"basic","max_results":1,"include_answer":false,"include_raw_content":false}')"

if [[ "$TAVILY_STATUS" != "200" ]] || ! grep -q '"results"' "$TAVILY_RESPONSE"; then
  print -u2 -- "Tavily smoke test failed (HTTP $TAVILY_STATUS)"
  exit 1
fi
print -r -- "Tavily search: OK (HTTP 200)"
