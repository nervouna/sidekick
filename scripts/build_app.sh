#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${SIDEKICK_BUILD_CONFIGURATION:-debug}"
CACHE_ROOT="$ROOT/.build/local-cache"
APP_PATH="$ROOT/build/Sidekick.app"
CONTENTS="$APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
APP_ICON_RESOURCES="$ROOT/Resources/AppIcon"

mkdir -p "$CACHE_ROOT/clang" "$CACHE_ROOT/swift"
export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/swift"

swift build --package-path "$ROOT" --configuration "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_DIR/Sidekick" "$MACOS/Sidekick"
cp "$APP_ICON_RESOURCES/Assets.car" "$RESOURCES/Assets.car"
cp "$APP_ICON_RESOURCES/Sidekick.icns" "$RESOURCES/Sidekick.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>Sidekick</string>
  <key>CFBundleExecutable</key>
  <string>Sidekick</string>
  <key>CFBundleIdentifier</key>
  <string>io.damao.sidekick</string>
  <key>CFBundleIconFile</key>
  <string>Sidekick</string>
  <key>CFBundleIconName</key>
  <string>Sidekick</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Sidekick</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$APP_PATH" >/dev/null
print -r -- "$APP_PATH"
