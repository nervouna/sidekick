#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
if [[ ! -f "$ROOT/.env" ]]; then
  print -u2 -- "Missing $ROOT/.env"
  exit 1
fi

set -a
source "$ROOT/.env"
set +a

APP_PATH="$(SIDEKICK_BUILD_CONFIGURATION=debug "$ROOT/scripts/build_app.sh" | tail -n 1)"
exec "$APP_PATH/Contents/MacOS/Sidekick"
