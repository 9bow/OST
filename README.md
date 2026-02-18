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
- Separate font size and color for original and translated text
- Configurable speech pause detection (0.5–5 seconds)
- Session history recording
- Menu bar app (no Dock icon)

## Requirements

- macOS 15.0 (Sequoia) or later
- Apple Silicon (arm64)
- Xcode Command Line Tools (`xcode-select --install`)

## Permissions

On first launch, macOS will prompt for:

- **Screen Recording** — for system audio capture
- **Speech Recognition** — for SFSpeechRecognizer

### Recommended Setup

- Download on-device speech model: System Settings > Keyboard > Dictation > Languages
- Download translation language pack: System Settings > General > Language & Region > Translation Languages

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

## Known Issues

- **Endpoint detection (EPD)** — Speech segmentation relies on a simple pause timer rather than proper endpoint detection. This means subtitle boundaries depend on silence duration, not linguistic structure, which can split mid-sentence or merge unrelated phrases.
- **Automatic language detection** — Auto-detect uses NLLanguageRecognizer on the first ~15 characters, which may misidentify the language from short or ambiguous input. Detection only runs once per session — if it picks the wrong language, the entire session uses the wrong recognizer.
- **Overlay blocks clicks even when empty** — The overlay window occupies its full frame area regardless of visible text content, which can block mouse interaction with underlying windows. Use "Lock Overlay" from the menu bar to toggle click-through.
- **Translation consistency** — Translation is triggered per speech pause, not per sentence. Short or fragmented pauses may produce less coherent translations. Context from recent entries is included to mitigate this, but long conversations may still show inconsistencies.
- **Speech recognition restart gap** — SFSpeechRecognizer's recognition task expires after ~60 seconds and auto-restarts, which may cause a brief gap in recognition.

## License

[MIT](LICENSE)
