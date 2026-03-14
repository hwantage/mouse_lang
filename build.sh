#!/bin/bash
set -euo pipefail

APP_NAME="MouseLang"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXECUTABLE_PATH="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
SIGN_IDENTITY="MouseLang Developer"
SELECTED_IDENTITY="-"

echo "🔨 Building $APP_NAME..."

if pgrep -f "$EXECUTABLE_PATH" >/dev/null 2>&1; then
    echo "Stopping running $APP_NAME..."
    pkill -f "$EXECUTABLE_PATH" || true
    sleep 1
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Compile Swift sources
swiftc \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -framework Cocoa \
    -framework Carbon \
    -framework ApplicationServices \
    -target arm64-apple-macosx13.0 \
    -O \
    Sources/main.swift \
    Sources/AppDelegate.swift \
    Sources/InputSourceManager.swift \
    Sources/IndicatorWindow.swift \
    Sources/Theme.swift \
    Sources/CaretTracker.swift

# Copy Info.plist
cp Info.plist "$APP_BUNDLE/Contents/"

if security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""; then
    SELECTED_IDENTITY="$SIGN_IDENTITY"
fi

# Clean out stale signing artifacts before re-signing in place.
rm -rf "$APP_BUNDLE/Contents/_CodeSignature"
find "$APP_BUNDLE/Contents" -name '*.cstemp' -delete 2>/dev/null || true

codesign --force --sign "$SELECTED_IDENTITY" "$APP_BUNDLE"

# Remove quarantine/provenance attributes that block Accessibility
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

codesign -vvv --verify "$APP_BUNDLE" >/dev/null

echo "✅ Build complete: $APP_BUNDLE"
echo "서명: $SELECTED_IDENTITY"
echo ""
echo "실행: open $APP_BUNDLE"
echo "종료: 상단 메뉴바 🌐 아이콘 → 종료"
