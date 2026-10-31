#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${OST_APP_BUNDLE:-$ROOT_DIR/DerivedData/Build/Products/Debug/OST.app}"
XPC="$APP/Contents/XPCServices/OSTModelDownloaderXPC.xpc"
MAIN_INFO="$ROOT_DIR/Xcode/OSTApp/Info.plist"
MAIN_ENTITLEMENTS="$ROOT_DIR/Xcode/OSTApp/OSTApp.entitlements"
XPC_INFO="$ROOT_DIR/Xcode/ModelDownloaderXPC/Info.plist"
XPC_ENTITLEMENTS="$ROOT_DIR/Xcode/ModelDownloaderXPC/ModelDownloaderXPC.entitlements"

plutil -lint "$MAIN_INFO" "$MAIN_ENTITLEMENTS" "$XPC_INFO" "$XPC_ENTITLEMENTS"

for key in \
  com.apple.security.network.client \
  com.apple.security.personal-information.accessibility; do
  if /usr/libexec/PlistBuddy -c "Print :$key" "$MAIN_ENTITLEMENTS" >/dev/null 2>&1; then
    echo "Main app source entitlements unexpectedly contain $key." >&2
    exit 1
  fi
done

for key in NSScreenCaptureUsageDescription NSSpeechRecognitionUsageDescription NSAccessibilityUsageDescription; do
  if plutil -extract "$key" raw "$MAIN_INFO" >/dev/null 2>&1; then
    echo "Main app Info.plist unexpectedly contains $key." >&2
    exit 1
  fi
done

plutil -extract NSAudioCaptureUsageDescription raw "$MAIN_INFO" >/dev/null
plutil -extract NSMicrophoneUsageDescription raw "$MAIN_INFO" >/dev/null
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.audio-input' "$MAIN_ENTITLEMENTS")" != "true" ]]; then
  echo "Main app source entitlements do not allow microphone input." >&2
  exit 1
fi
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$XPC_ENTITLEMENTS" >/dev/null

for key in \
  com.apple.security.device.audio-input \
  com.apple.security.personal-information.accessibility \
  com.apple.security.files.user-selected.read-write; do
  if /usr/libexec/PlistBuddy -c "Print :$key" "$XPC_ENTITLEMENTS" >/dev/null 2>&1; then
    echo "Downloader XPC source entitlements unexpectedly contain $key." >&2
    exit 1
  fi
done

for key in NSAudioCaptureUsageDescription NSMicrophoneUsageDescription NSScreenCaptureUsageDescription; do
  if plutil -extract "$key" raw "$XPC_INFO" >/dev/null 2>&1; then
    echo "Downloader XPC Info.plist unexpectedly contains $key." >&2
    exit 1
  fi
done

if /usr/bin/grep -Eq 'PCMChunk|TranscriptSegment|sourceText|translatedText|audio' \
  "$ROOT_DIR/Sources/OSTCore/XPC/ModelDownloaderXPC.swift"; then
  echo "XPC protocol source unexpectedly exposes user-content types." >&2
  exit 1
fi

echo "Static privacy boundary checks passed."

if [[ "${1:-}" == "--static" ]]; then
  exit 0
fi

if [[ ! -d "$APP" || ! -d "$XPC" ]]; then
  echo "Build OST.app with the embedded XPC service first." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvvv --entitlements - "$APP"
codesign -dvvv --entitlements - "$XPC"
plutil -p "$APP/Contents/Info.plist"
plutil -p "$XPC/Contents/Info.plist"

if codesign -d --entitlements - "$APP" 2>&1 | /usr/bin/grep -Eq 'com.apple.security.network.client'; then
  echo "Main app unexpectedly has outbound network entitlement." >&2
  exit 1
fi

if ! codesign -d --entitlements - "$APP" 2>&1 | /usr/bin/grep -Eq 'com.apple.security.device.audio-input'; then
  echo "Signed main app does not allow microphone input." >&2
  exit 1
fi
plutil -extract NSMicrophoneUsageDescription raw "$APP/Contents/Info.plist" >/dev/null

if ! codesign -d --entitlements - "$XPC" 2>&1 | /usr/bin/grep -Eq 'com.apple.security.network.client'; then
  echo "Downloader XPC is missing outbound network entitlement." >&2
  exit 1
fi

for key in \
  com.apple.security.device.audio-input \
  com.apple.security.personal-information.accessibility \
  com.apple.security.files.user-selected.read-write; do
  if codesign -d --entitlements - "$XPC" 2>&1 | /usr/bin/grep -Eq "$key"; then
    echo "Signed downloader XPC unexpectedly contains $key." >&2
    exit 1
  fi
done
