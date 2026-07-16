#!/bin/zsh
set -euo pipefail

APP_PATH="${1:?usage: scripts/test_app_bundle.sh /path/to/Sidekick.app}"
INFO="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/Sidekick"
RESOURCES="$APP_PATH/Contents/Resources"

[[ -f "$INFO" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$RESOURCES/Assets.car" ]]
[[ -f "$RESOURCES/Sidekick.icns" ]]
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$INFO")" == "io.damao.sidekick" ]]
[[ "$(plutil -extract CFBundleIconFile raw -o - "$INFO")" == "Sidekick" ]]
[[ "$(plutil -extract CFBundleIconName raw -o - "$INFO")" == "Sidekick" ]]
[[ "$(plutil -extract LSUIElement raw -o - "$INFO")" == "true" ]]
[[ "$(plutil -extract LSMinimumSystemVersion raw -o - "$INFO")" == "14.0" ]]
if find "$APP_PATH" -name '.env' -print -quit | grep -q .; then
  print -u2 -- ".env must not be included in the App Bundle"
  exit 1
fi
codesign --verify --deep --strict "$APP_PATH"
if [[ "${SIDEKICK_REQUIRE_DEVELOPER_ID:-0}" == "1" ]]; then
  SIGNING_DETAILS="$(codesign -dvv "$APP_PATH" 2>&1)"
  if ! grep -q '^Authority=Developer ID Application:' <<< "$SIGNING_DETAILS"; then
    print -u2 -- "App must be signed with a Developer ID Application identity"
    exit 1
  fi
  if ! grep -Eq '^TeamIdentifier=.+$' <<< "$SIGNING_DETAILS"; then
    print -u2 -- "Developer ID signed App must include a TeamIdentifier"
    exit 1
  fi
fi
print -r -- "Bundle verified: $APP_PATH"
