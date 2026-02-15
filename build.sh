#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ScreenHighlighter"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
PLIST_DIR="$APP_DIR/Contents"
BIN_PATH="$BIN_DIR/$APP_NAME"

mkdir -p "$BIN_DIR"

cat > "$PLIST_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ScreenHighlighter</string>
    <key>CFBundleDisplayName</key>
    <string>ScreenHighlighter</string>
    <key>CFBundleIdentifier</key>
    <string>local.codex.screenhighlighter</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>ScreenHighlighter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

swiftc "$ROOT_DIR/ScreenHighlighter.swift" \
  -o "$BIN_PATH" \
  -framework AppKit

codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "Built: $APP_DIR"
