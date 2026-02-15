#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ScreenHighlighter"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
BIN_PATH="$BIN_DIR/$APP_NAME"
PLIST_DIR="$APP_DIR/Contents"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

echo "=== ScreenHighlighter 배포 패키지 빌드 ==="

# 1. .app 번들 디렉토리 생성
mkdir -p "$BIN_DIR"

# 2. Info.plist 생성
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

# 3. Apple Silicon (arm64) 릴리스 빌드
echo "→ Apple Silicon (arm64) 릴리스 빌드 중..."
swiftc "$ROOT_DIR/ScreenHighlighter.swift" \
  -o "$BIN_PATH" \
  -target arm64-apple-macosx13.0 \
  -O \
  -framework AppKit

# 4. 코드 서명
codesign --force --deep --sign - "$APP_DIR" >/dev/null
echo "→ 코드 서명 완료"

# 5. 기존 DMG 제거
[ -f "$DMG_PATH" ] && rm "$DMG_PATH"

# 6. DMG 생성 (Applications 바로가기 포함)
echo "→ DMG 패키지 생성 중..."
DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" \
  > /dev/null

rm -rf "$DMG_STAGING"

echo ""
echo "=== 완료! ==="
echo "📦 DMG 파일: $DMG_PATH"
echo ""
echo "사용법:"
echo "  1. DMG 파일을 다른 맥북으로 복사 (AirDrop, USB 등)"
echo "  2. DMG를 더블클릭하여 열기"
echo "  3. ScreenHighlighter.app을 Applications 폴더로 드래그"
echo "  4. 처음 실행 시: 우클릭 → 열기 (Gatekeeper 우회)"
echo "  5. 시스템 설정 → 개인정보 보호 → 손쉬운 사용에서 권한 허용"
