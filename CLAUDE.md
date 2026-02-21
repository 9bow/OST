# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Full build → produces build/OST.app
./build.sh

# Type-check only (no binary)
./build.sh --typecheck

# Clean build
./build.sh --clean

# Run the app
open build/OST.app

# If macOS blocks execution
xattr -dr com.apple.quarantine build/OST.app
```

No Xcode project is used for building. The `build.sh` script compiles all 22 Swift source files together via `xcrun swiftc` (CommandLineTools SDK, arm64, macOS 15.0 target). There is no test suite, package manager, or linter configured.

**Adding new source files**: When creating a new `.swift` file, you must also add it to the `SOURCES` array in `build.sh` — the compiler only sees files listed there.

## Architecture

OST is a macOS menu bar app (`LSUIElement=true`) that captures system audio, performs real-time speech recognition, and displays translated subtitles in a floating overlay.

### Data Pipeline

```
ScreenCaptureKit (16kHz mono) → SpeechRecognizer → AppState → TranslationService → SubtitleView overlay
     SystemAudioCapture              SFSpeech          entries      Translation.framework     NSPanel
```

- **SystemAudioCapture** — Uses SCStream (audio-only, minimal 2x2 video) to produce `AsyncStream<CMSampleBuffer>`. A fresh stream is created per capture session.
- **SpeechRecognizer** — `@MainActor` wrapper around `SFSpeechRecognizer`. Publishes `currentText` (partial) and `finalizedText` (confirmed). Auto-restarts recognition after each final result or transient error for continuous listening. Note: `isFinal` only fires when the recognition task ends (~60s timeout), not per sentence — AppState uses a Combine-based debounce timer on `currentText` to detect speech pauses and create subtitle entries.
- **AppState** — Central `@MainActor ObservableObject`. Owns the pipeline lifecycle. Detects speech pauses via a debounce timer on `currentText`, then creates `SubtitleEntry` items for translation. Also extracts complete sentences immediately when punctuation boundaries are detected (before the pause timer fires). Manages time-based expiry and max-line trimming. Uses Combine `.sink` (not `AsyncPublisher`) to bind speech output. Supports automatic language detection via `NaturalLanguage` framework (switches recognizer locale after detecting spoken language from initial text).
- **TranslationService** — Wraps `TranslationSession`. The session is injected by SwiftUI's `.translationTask` modifier on `SubtitleView`, so the overlay must be shown *before* capture starts. Falls back to free Google Translate API when no `TranslationSession` is available.
- **SubtitleView / OverlayWindow** — `NSPanel` (borderless, floating, click-through when locked) hosting SwiftUI content via `NSHostingView` wrapped in a plain `NSView` container (prevents hosting view from driving window resizes). Entries animate in/out with rolling display. Smart auto-scroll: locked mode always scrolls to bottom; unlocked mode pauses auto-scroll when user scrolls up, resumes when they return to bottom.

### Key Constraints

- **Audio format**: SCStream must output 16kHz mono PCM — SFSpeechRecognizer silently fails on 48kHz float32.
- **On-device recognition**: Check `supportsOnDeviceRecognition` before setting `requiresOnDeviceRecognition = true`; missing models produce zero results with no error.
- **Translation session lifecycle**: `.translationTask` only fires when its view is rendered. The overlay window must be visible before `startCapture()` is called.
- **Threading**: Recognition callbacks arrive on arbitrary threads; all UI updates go through `Task { @MainActor in }`. `AppLogger` requires `nonisolated static func post()` for off-main-thread logging.
- **Recognition task restart timing**: When restarting the recognition task (every ~60s), the new `SFSpeechAudioBufferRecognitionRequest` must be created and swapped into `recognitionRequest` *before* cancelling the old task. Otherwise audio buffers arriving from the continuous stream are silently dropped during the gap.
- **Combine sink synchronization**: `extractCompleteSentences` receives `sinkCurrentText` (the value delivered by the Combine sink) rather than reading `speechRecognizer.currentText` directly, which may have changed asynchronously between delivery and execution.

### Source Layout

```
OST/Sources/
├── App/           AppState (pipeline coordinator), OSTApp (entry point), WindowManager, Logger, SessionRecorder
├── Audio/         SystemAudioCapture (ScreenCaptureKit)
├── Speech/        SpeechRecognizer (SFSpeech), SupportedLanguages
├── Translation/   TranslationService, TranslationConfig (availability check)
├── Settings/      UserSettings (@AppStorage persistence, color serialization)
├── UI/            SubtitleView, RecognitionOverlayView, TranslationOverlayView, OverlayWindow, MenuBarView, SettingsView, FontSettingsView, LanguagePickerView, LogViewerView, SessionHistoryView
└── Accessibility/ AccessibilityManager
```

### Window Management

`WindowManager` is a centralized coordinator for all windows (overlay, settings, logs, session history). It reuses existing visible windows instead of creating duplicates. The overlay is borderless/floating; other windows are standard with specific sizing.

The overlay window supports lock/unlock toggling: locked = click-through (`ignoresMouseEvents = true`), unlocked = movable/resizable. `resetOverlay()` restores default position/size and re-locks.

### Settings Persistence

`UserSettings` uses `@AppStorage` for all preferences. Colors are serialized via `NSKeyedArchiver`/`NSKeyedUnarchiver` since `@AppStorage` doesn't natively support `Color`. Overlay frame position/size is persisted and restored on launch.

### Text Processing Pipeline

AppState processes speech text through two mechanisms:
1. **Sentence extraction** — When punctuation creates 2+ sentence boundaries in `liveText`, all complete sentences are immediately consumed as subtitle entries. The last (in-progress) sentence remains as `liveText`.
2. **Pause-based consumption** — A configurable debounce timer consumes remaining `liveText` after a speech pause (default 2s).

Between recognition task restarts (~60s cycle), `lastConsumedTail` preserves the tail of the previous session's text to detect and strip overlapping content from the new session.

## Initialization Order (Race Condition)

`startCapture()` in `OSTApp.swift` must follow this exact sequence:
1. Show overlay window (`windowManager.showOverlay`) — attaches `.translationTask` modifier
2. Wait ~200ms for SwiftUI to render (`try? await Task.sleep`)
3. Configure translation service (`translationService.configure`)
4. Start audio capture (`appState.startCapture`)

Skipping step 2 or reordering causes `.translationTask` to never fire, silently breaking translation.

## Frameworks Used

AppKit, SwiftUI, Speech, ScreenCaptureKit, CoreMedia, Translation, Combine, NaturalLanguage

## Required Permissions

- **Screen Recording** (for system audio capture via ScreenCaptureKit)
- **Speech Recognition** (for SFSpeechRecognizer)

## Multilingual README

README is maintained in 4 languages. When modifying `README.md`, apply the same changes to all translations:

- `README.md` — English (primary)
- `README.ko.md` — 한국어
- `README.zh.md` — 中文
- `README.ja.md` — 日本語

Each file has a language selector at the top. Code blocks, URLs, image paths, and CLI commands should remain identical across all versions.
