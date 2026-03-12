#!/bin/bash
set -e

APP_NAME="MouseLang"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME..."

# Clean previous build
rm -rf "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Compile Swift sources
swiftc \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -framework Cocoa \
    -framework Carbon \
    -target arm64-apple-macosx13.0 \
    -O \
    Sources/main.swift \
    Sources/AppDelegate.swift \
    Sources/InputSourceManager.swift \
    Sources/IndicatorWindow.swift \
    Sources/Theme.swift

# Copy Info.plist
cp Info.plist "$APP_BUNDLE/Contents/"

echo "✅ Build complete: $APP_BUNDLE"
echo ""
echo "실행: open $APP_BUNDLE"
echo "종료: 상단 메뉴바 🌐 아이콘 → 종료"
