#!/bin/bash
set -e

APP_NAME="MouseLang"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME..."

# Create app bundle structure (don't clean — preserves Accessibility permission)
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

# Code sign with stable developer identity (preserves Accessibility permission across rebuilds)
codesign --force --sign "MouseLang Developer" "$APP_BUNDLE"

# Remove quarantine/provenance attributes that block Accessibility
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

echo "✅ Build complete: $APP_BUNDLE"
echo ""
echo "실행: open $APP_BUNDLE"
echo "종료: 상단 메뉴바 🌐 아이콘 → 종료"
