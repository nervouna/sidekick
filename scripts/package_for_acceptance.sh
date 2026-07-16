#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_PATH="$ROOT/build/Sidekick.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT/build/Sidekick.app/Contents/Info.plist" 2>/dev/null || print -r -- "0.1.0")"
ARCHIVE_PATH="$ROOT/dist/Sidekick-${VERSION}-macos-arm64-developer-id.zip"

if [[ -n "${SIDEKICK_CODE_SIGN_IDENTITY:-}" ]]; then
  IDENTITY="$SIDEKICK_CODE_SIGN_IDENTITY"
else
  IDENTITIES="$(security find-identity -v -p codesigning | awk '/"Developer ID Application:/ { print $2 }')"
  IDENTITY_COUNT="$(grep -c . <<< "$IDENTITIES" || true)"
  if [[ "$IDENTITY_COUNT" != "1" ]]; then
    print -u2 -- "Expected exactly one available Developer ID Application identity; found $IDENTITY_COUNT"
    exit 1
  fi
  IDENTITY="$IDENTITIES"
fi

SIDEKICK_BUILD_CONFIGURATION=release \
SIDEKICK_CODE_SIGN_IDENTITY="$IDENTITY" \
"$ROOT/scripts/build_app.sh" >/dev/null

SIDEKICK_REQUIRE_DEVELOPER_ID=1 "$ROOT/scripts/test_app_bundle.sh" "$APP_PATH"
mkdir -p "$ROOT/dist"
rm -f "$ARCHIVE_PATH"
ditto -c -k --keepParent --norsrc --noextattr "$APP_PATH" "$ARCHIVE_PATH"

print -r -- "$ARCHIVE_PATH"
