#!/bin/bash
set -euo pipefail

# OST Build Script
# Builds the On-Screen Translator app from CLI using swiftc

APP_NAME="OST"
BUNDLE_ID="com.ost.on-screen-translator"
VERSION="0.1.0"
BUILD_VERSION="1"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
ENTITLEMENTS="OST/Resources/OST.entitlements"

DEPLOY_TARGET="15.0"
SWIFT_VERSION="5"

FRAMEWORKS=(
    -framework AppKit
    -framework SwiftUI
    -framework Speech
    -framework ScreenCaptureKit
    -framework CoreMedia
    -framework Translation
    -framework NaturalLanguage
)

SOURCES=(
    OST/Sources/Settings/UserSettings.swift
    OST/Sources/Speech/SupportedLanguages.swift
    OST/Sources/Audio/SystemAudioCapture.swift
    OST/Sources/Speech/SpeechRecognizer.swift
    OST/Sources/Translation/TranslationConfig.swift
    OST/Sources/Translation/TranslationService.swift
    OST/Sources/App/Logger.swift
    OST/Sources/App/SessionRecorder.swift
    OST/Sources/App/AppState.swift
    OST/Sources/App/WindowManager.swift
    OST/Sources/Accessibility/AccessibilityManager.swift
    OST/Sources/UI/SubtitleView.swift
    OST/Sources/UI/RecognitionOverlayView.swift
    OST/Sources/UI/TranslationOverlayView.swift
    OST/Sources/UI/OverlayWindow.swift
    OST/Sources/UI/FontSettingsView.swift
    OST/Sources/UI/LanguagePickerView.swift
    OST/Sources/UI/MenuBarView.swift
    OST/Sources/UI/LogViewerView.swift
    OST/Sources/UI/SessionHistoryView.swift
    OST/Sources/UI/SettingsView.swift
    OST/Sources/App/OSTApp.swift
)

# Parse arguments
TYPECHECK_ONLY=false
CLEAN=false
for arg in "$@"; do
    case "$arg" in
        --typecheck) TYPECHECK_ONLY=true ;;
        --clean) CLEAN=true ;;
        --help|-h)
            echo "Usage: ./build.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --typecheck  Type-check only (no binary output)"
            echo "  --clean      Remove build directory before building"
            echo "  -h, --help   Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Run ./build.sh --help for usage." >&2
            exit 1
            ;;
    esac
done

SDK_PATH=$(xcrun --show-sdk-path)
TARGET="arm64-apple-macosx${DEPLOY_TARGET}"

echo "=== OST Build ==="
echo "SDK: $SDK_PATH"
echo "Target: $TARGET"

# Clean
if $CLEAN && [ -d "$BUILD_DIR" ]; then
    echo "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
fi

# Type-check only
if $TYPECHECK_ONLY; then
    echo "Type-checking ${#SOURCES[@]} files..."
    xcrun swiftc \
        -swift-version "$SWIFT_VERSION" \
        -warnings-as-errors \
        -warn-concurrency \
        -strict-concurrency=complete \
        -target "$TARGET" \
        -sdk "$SDK_PATH" \
        -typecheck \
        "${SOURCES[@]}"
    echo "Type-check passed."
    exit 0
fi

# Build
echo "Compiling ${#SOURCES[@]} files..."

if [ -d "$APP_BUNDLE" ]; then
    echo "Removing previous app bundle..."
    rm -rf "$APP_BUNDLE"
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

xcrun swiftc \
    -swift-version "$SWIFT_VERSION" \
    -warnings-as-errors \
    -warn-concurrency \
    -strict-concurrency=complete \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -o "$MACOS_DIR/$APP_NAME" \
    "${FRAMEWORKS[@]}" \
    "${SOURCES[@]}"

echo "Binary built: $MACOS_DIR/$APP_NAME"
for framework in AppKit SwiftUI Speech ScreenCaptureKit CoreMedia Translation NaturalLanguage; do
    otool -L "$MACOS_DIR/$APP_NAME" | grep -q "/${framework}.framework/" \
        || { echo "Missing linked framework: $framework" >&2; exit 1; }
done

# Create Info.plist with resolved variables
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>On-Screen Translator</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${DEPLOY_TARGET}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>OST needs speech recognition access to transcribe system audio in real-time.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>OST needs system audio capture access to transcribe and translate audio in real-time.</string>
    <key>NSSystemAudioRecordingUsageDescription</key>
    <string>OST needs system audio recording access to capture audio for transcription and translation.</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist" >/dev/null
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$CONTENTS/Info.plist")" = "$APP_NAME"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$CONTENTS/Info.plist")" = "On-Screen Translator"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS/Info.plist")" = "$BUNDLE_ID"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CONTENTS/Info.plist")" = "$BUILD_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$CONTENTS/Info.plist")" = "$DEPLOY_TARGET"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$CONTENTS/Info.plist")" = "true"
test -n "$(/usr/libexec/PlistBuddy -c 'Print :NSSpeechRecognitionUsageDescription' "$CONTENTS/Info.plist")"
test -n "$(/usr/libexec/PlistBuddy -c 'Print :NSAudioCaptureUsageDescription' "$CONTENTS/Info.plist")"
test -n "$(/usr/libexec/PlistBuddy -c 'Print :NSSystemAudioRecordingUsageDescription' "$CONTENTS/Info.plist")"
echo "Info.plist created with resolved variables"

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"
test -x "$MACOS_DIR/$APP_NAME"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$CONTENTS/Info.plist")" = "$APP_NAME"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$CONTENTS/Info.plist")" = "APPL"
test "$(cat "$CONTENTS/PkgInfo")" = "APPL????"

# Sign and verify the app bundle with an ad-hoc signature
plutil -lint "$ENTITLEMENTS" >/dev/null
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
codesign -d --entitlements :- "$APP_BUNDLE" > "$BUILD_DIR/codesign-entitlements.plist" 2>/dev/null
plutil -lint "$BUILD_DIR/codesign-entitlements.plist" >/dev/null
test "$(plutil -convert json -o - "$BUILD_DIR/codesign-entitlements.plist")" = "$(plutil -convert json -o - "$ENTITLEMENTS")"
rm -f "$BUILD_DIR/codesign-entitlements.plist"

# Remove quarantine attribute if present
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "=== Build Complete ==="
echo "App bundle: $APP_BUNDLE"
echo ""
echo "Run with: open $APP_BUNDLE"
echo ""
echo "If macOS blocks the app, run:"
echo "  xattr -dr com.apple.quarantine $APP_BUNDLE"
