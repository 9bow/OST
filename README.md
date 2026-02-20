# OST — On-Screen Translator

Real-time speech recognition and translation overlay for macOS.

Captures system audio, transcribes speech using Apple's Speech framework, and displays translated subtitles in a floating overlay window. Works with any audio source — YouTube, podcasts, Zoom/Teams meetings, and more.

## Screenshots

![Translation overlay on YouTube video](assets/overlay-demo.png)

<details>
<summary>More screenshots</summary>

| Menu Bar | Settings — Display |
|:---:|:---:|
| ![Menu bar](assets/menubar.png) | ![Display settings](assets/settings-display.png) |

| Settings — Languages | Settings — Setup |
|:---:|:---:|
| ![Language settings](assets/settings-languages.png) | ![Setup prerequisites](assets/settings-setup.png) |

| Session History |
|:---:|
| ![Session history](assets/session-history.png) |

</details>

## Disclaimer

This project was entirely written by [Claude](https://claude.ai/) (Anthropic's AI assistant). The code, build scripts, documentation, and CI/CD configuration were all generated through AI-assisted development. While functional, the code has not undergone formal human code review — use at your own discretion.

## Features

- Real-time system audio capture via ScreenCaptureKit
- Speech-to-text using SFSpeechRecognizer (on-device or server-based)
- Translation via Apple Translation framework (with Google Translate fallback)
- Floating, resizable overlay with customizable appearance
- Lock/Unlock overlay: locked = click-through, unlocked = move/resize/scroll
- Scrollable subtitle history (unlock mode)
- Separate font size and color for original and translated text
- Configurable background color, opacity, speech pause, subtitle expiry
- Automatic language detection (English, Korean, Japanese, Chinese)
- Sentence-based text segmentation with pause detection
- Duplicate text overlap detection on recognition restart
- Session history recording with export
- Menu bar app (no Dock icon)

## Requirements

- macOS 15.0 (Sequoia) or later
- Apple Silicon (arm64)
- Xcode Command Line Tools (`xcode-select --install`)

## Setup Guide

### 1. Required Permissions

On first launch, macOS will prompt for the following permissions. If not prompted, enable them manually:

| Permission | Purpose | Path |
|---|---|---|
| **Screen Recording** | System audio capture via ScreenCaptureKit | System Settings > Privacy & Security > Screen Recording |
| **Speech Recognition** | SFSpeechRecognizer access | System Settings > Privacy & Security > Speech Recognition |

### 2. Enable Siri & Dictation

Speech recognition (especially server-based) requires Siri & Dictation to be enabled:

- **System Settings > Siri & Spotlight > Siri** — Turn on (or "Listen for...")
- If using on-device recognition, Siri does not need to be active, but the speech model must be downloaded (see step 3)

### 3. Download On-Device Speech Model (Recommended)

For faster, offline, and more reliable recognition:

- **System Settings > General > Keyboard > Dictation > Languages**
- Download the speech model for your source language (e.g., English, Korean, Japanese)
- After download, enable "On-device recognition" in OST Settings > Debug tab

> Without the on-device model, server-based recognition is used (requires internet, may have higher latency).

### 4. Download Translation Language Pack (Recommended)

For offline translation using Apple Translation framework:

- **System Settings > General > Language & Region > Translation Languages**
- Download the language pair you need (e.g., English ↔ Korean)

> Without the translation pack, OST falls back to the Google Translate API (requires internet).

## Build

```bash
# Full build → produces build/OST.app
./build.sh

# Type-check only
./build.sh --typecheck

# Clean build
./build.sh --clean

# Run
open build/OST.app
```

No Xcode project is required. The build script compiles all Swift sources via `xcrun swiftc`.

## Architecture

```
ScreenCaptureKit (16kHz mono) → SpeechRecognizer → AppState → TranslationService → SubtitleView
```

### Source Layout

```
OST/Sources/
├── App/           AppState, OSTApp, WindowManager, Logger, SessionRecorder
├── Audio/         SystemAudioCapture (ScreenCaptureKit)
├── Speech/        SpeechRecognizer, SupportedLanguages
├── Translation/   TranslationService, TranslationConfig
├── Settings/      UserSettings
├── UI/            SubtitleView, OverlayWindow, MenuBarView, SettingsView, etc.
└── Accessibility/ AccessibilityManager
```

## Usage Tips

- **Lock/Unlock**: Use the menu bar toggle or Settings > Display to switch overlay modes
  - **Locked**: Overlay is click-through — interact with windows behind it normally
  - **Unlocked**: Drag to move, resize edges, scroll through subtitle history
- **Reset Overlay**: If the overlay becomes invisible or mispositioned, use Settings > Display > "Reset Overlay Position & Size"
- **Scroll behavior**: Auto-scrolls to latest text by default. Scroll up to pause auto-scroll; scroll back to bottom to resume

## Known Issues

- **Endpoint detection (EPD)** — Speech segmentation uses a pause timer combined with sentence boundary detection, not proper endpoint detection. Subtitle boundaries may sometimes split mid-sentence or merge unrelated phrases.
- **Automatic language detection** — Auto-detect uses NLLanguageRecognizer on the first ~15 characters, which may misidentify the language from short or ambiguous input. Detection only runs once per session.
- **Translation consistency** — Translation is triggered per speech segment. Short or fragmented segments may produce less coherent translations.
- **Speech recognition restart gap** — SFSpeechRecognizer's recognition task expires after ~60 seconds and auto-restarts. Overlap detection minimizes duplicate text, but a brief gap in recognition may still occur.

## License

[MIT](LICENSE)
