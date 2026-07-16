#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
if [[ ! -f "$ROOT/.env" ]]; then
  print -u2 -- "Missing $ROOT/.env"
  exit 2
fi

set -a
source "$ROOT/.env"
set +a

: "${DEEPSEEK_API_KEY:?DEEPSEEK_API_KEY is missing}"

exec swift run --package-path "$ROOT" SidekickPromptEval
