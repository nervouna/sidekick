#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CACHE_ROOT="$ROOT/.build/local-cache"
mkdir -p "$CACHE_ROOT/clang" "$CACHE_ROOT/swift"
export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/swift"

swift test --package-path "$ROOT"
APP_PATH="$(SIDEKICK_BUILD_CONFIGURATION=release "$ROOT/scripts/build_app.sh" | tail -n 1)"
"$ROOT/scripts/test_app_bundle.sh" "$APP_PATH"
