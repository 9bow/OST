import OSTCore
@testable import OST
import Foundation
import SwiftUI
import XCTest

final class OSTTests: XCTestCase {
    func testBundledCatalogIsValid() throws {
        let catalog = try ModelCatalog.bundled()
        XCTAssertEqual(catalog.models.count, 4)
        XCTAssertNoThrow(try catalog.validate())
    }

    func testMLXMetalLibraryIsColocatedWithExecutable() throws {
        let executable = try XCTUnwrap(Bundle.main.executableURL)
        let metalLibrary = executable.deletingLastPathComponent().appending(path: "mlx.metallib")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metalLibrary.path))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: metalLibrary.path),
            "../Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        )
    }

    func testMainPrivacyDefaults() {
        let snapshot = PreferencesSnapshot()
        XCTAssertFalse(snapshot.overlayLocked)
        XCTAssertEqual(snapshot.backgroundOpacity, 0.65)
        XCTAssertEqual(snapshot.sourceFontSize, 20)
        XCTAssertEqual(snapshot.translationFontSize, 28)
        XCTAssertEqual(snapshot.appDisplayLanguage, .english)
        XCTAssertFalse(snapshot.sessionLoggingEnabled)
        XCTAssertNil(snapshot.sessionLogDirectoryBookmark)
        XCTAssertEqual(snapshot.microphoneMode, .off)
    }

    @MainActor
    func testMicrophoneModeAndColorPersist() {
        let suiteName = "OSTTests.microphone.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(userDefaults: defaults)
        let color = RGBAColor(red: 0.1, green: 0.8, blue: 0.4, alpha: 0.8)
        for mode in MicrophoneMode.allCases {
            preferences.microphoneMode = mode
            preferences.microphoneColor = color
            let restored = PreferencesStore(userDefaults: defaults)
            XCTAssertEqual(restored.microphoneMode, mode)
            XCTAssertEqual(restored.microphoneColor, color)
        }
    }

    @MainActor
    func testMicrophoneTranscriptionOnlySkipsTranslationUntilNextSession() async {
        let suiteName = "OSTTests.microphone-routing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(userDefaults: defaults)
        preferences.targetLanguage = .english
        let scheduler = TranslationScheduler()
        let model = AppModel(preferences: preferences, translationScheduler: scheduler)
        defer { model.toggleOverlayVisibility() }
        var updates = scheduler.updates.makeAsyncIterator()

        model.overlayState.microphoneMode = .transcription
        preferences.microphoneMode = .transcriptionAndTranslation
        let microphone = TranscriptSegment(
            startTime: .zero, language: .english, sourceText: "My speech", isFinal: true,
            audioSource: .microphone
        )
        let system = TranscriptSegment(
            startTime: .zero, language: .english, sourceText: "System speech", isFinal: true
        )
        await model.handleTranscript(.segment(microphone))
        await model.handleTranscript(.segment(system))
        let systemUpdate = await updates.next()
        XCTAssertEqual(systemUpdate, .translated(
            segmentID: system.id, text: system.sourceText, isFinal: true, provider: nil
        ))
        XCTAssertEqual(model.overlayState.segments.count, 2)

        model.overlayState.microphoneMode = .transcriptionAndTranslation
        await model.handleTranscript(.segment(microphone))
        let microphoneUpdate = await updates.next()
        XCTAssertEqual(microphoneUpdate, .translated(
            segmentID: microphone.id, text: microphone.sourceText, isFinal: true, provider: nil
        ))
    }

    @MainActor
    func testMicrophoneHistoryAndSimultaneousPreviewsRenderInTheirOwnColor() async throws {
        let suiteName = "OSTTests.microphone-render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(userDefaults: defaults)
        preferences.microphoneMode = .transcriptionAndTranslation
        preferences.microphoneColor = RGBAColor(red: 1, green: 0, blue: 1)
        preferences.sourceColor = .white
        preferences.translationColor = .white
        preferences.previewColor = .white
        let state = OverlayState()
        state.isListening = true
        state.segments = AudioSource.allCases.flatMap { source in
            [true, false].map { isFinal in
                TranscriptSegment(
                    startTime: .zero,
                    language: .english,
                    sourceText: "\(source.rawValue) \(isFinal ? "confirmed transcript" : "live transcript")",
                    translatedText: "\(source.rawValue) \(isFinal ? "confirmed translation" : "live translation")",
                    isFinal: isFinal,
                    audioSource: source
                )
            }
        }
        for kind in [OverlayPanelKind.combined, .source, .translation] {
            let host = NSHostingView(rootView: OverlayContentView(
                kind: kind, state: state, preferences: preferences, isSettingsPreview: true
            ).frame(width: 720, height: 500))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = host
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(bitmap)
            var coloredPixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       color.redComponent > 0.5, color.greenComponent < 0.2, color.blueComponent > 0.5 {
                        coloredPixels += 1
                    }
                }
            }
            XCTAssertGreaterThan(coloredPixels, 100)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Microphone \(kind)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testFirstLaunchOverlayIsUnlockedAndSavedChoicePersists() {
        let suiteName = "OSTTests.first-launch-overlay.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunch = PreferencesStore(userDefaults: defaults)
        XCTAssertFalse(firstLaunch.overlayLocked)
        firstLaunch.overlayLocked = true

        let restored = PreferencesStore(userDefaults: defaults)
        XCTAssertTrue(restored.overlayLocked)
    }

    @MainActor
    func testSubtitleDisplayModePersists() {
        let suiteName = "OSTTests.subtitle-display.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(userDefaults: defaults)
        XCTAssertEqual(preferences.subtitleDisplayMode, .both)

        for mode in SubtitleDisplayMode.allCases {
            preferences.subtitleDisplayMode = mode
            XCTAssertEqual(PreferencesStore(userDefaults: defaults).subtitleDisplayMode, mode)
        }
    }

    @MainActor
    func testTranscriptionVocabularyPersistsAcrossProviderChangesAndCanBeCleared() {
        let suiteName = "OSTTests.vocabulary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(userDefaults: defaults)
        XCTAssertEqual(preferences.transcriptionVocabulary, "")
        preferences.transcriptionVocabulary = "PyTorch\n파이토치\n"
        preferences.selectTranscriptionProvider(.qwen3ASR)
        preferences.selectTranscriptionProvider(.appleSpeech)

        let restored = PreferencesStore(userDefaults: defaults)
        XCTAssertEqual(restored.transcriptionVocabulary, "PyTorch\n파이토치\n")
        restored.transcriptionVocabulary = String(repeating: "가", count: 4_001)
        XCTAssertEqual(PreferencesStore(userDefaults: defaults).transcriptionVocabulary.count, 4_000)
        restored.transcriptionVocabulary = ""
        XCTAssertEqual(PreferencesStore(userDefaults: defaults).transcriptionVocabulary, "")
    }

    @MainActor
    func testSubtitleDisplayModeUpdatesVisiblePanels() {
        let suiteName = "OSTTests.subtitle-panels.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(userDefaults: defaults)
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let coordinator = OverlayCoordinator(
            state: OverlayState(),
            preferences: preferences,
            translationPackCoordinator: TranslationPackCoordinator()
        )
        defer { coordinator.hide() }

        for layout in OverlayLayout.allCases {
            preferences.overlayLayout = layout
            for mode in SubtitleDisplayMode.allCases + [.both] {
                preferences.subtitleDisplayMode = mode
                coordinator.applyPreferences()
                let visibleTitles = Set(NSApp.windows.filter {
                    !existingWindows.contains(ObjectIdentifier($0)) && $0.isVisible
                }.map(\.title))
                var expected: Set<String> = []
                if layout == .combined {
                    expected.insert("OST Subtitles")
                } else {
                    if mode != .translationOnly { expected.insert("OST Transcript") }
                    if mode != .sourceOnly { expected.insert("OST Translation") }
                }
                XCTAssertEqual(visibleTitles, expected, "\(layout.rawValue), \(mode.rawValue)")
            }
        }
    }

    @MainActor
    func testSavedAutomaticInputIsRepairedWhenAppleSpeechIsSelected() throws {
        let suiteName = "OSTTests.apple-speech-input.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let snapshot = PreferencesSnapshot(
            sourceMode: .automatic,
            transcriptionProvider: .appleSpeech
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "OST.preferences.v1")

        let restored = PreferencesStore(userDefaults: defaults)

        guard case .fixed = restored.sourceMode else {
            return XCTFail("Apple Speech must not retain the unsupported automatic input mode")
        }
        XCTAssertEqual(restored.transcriptionProvider, .appleSpeech)

        restored.sourceMode = .automatic
        restored.selectTranscriptionProvider(.appleSpeech)
        guard case .fixed = restored.sourceMode else {
            return XCTFail("Selecting Apple Speech must repair automatic input immediately")
        }
    }

    func testAppleTranslationDisclosureIsLocalized() {
        let key = "When Apple Translation is used, macOS may send Apple non-content technical information such as the app identifier and selected language pair. Your audio, transcript, and translation text are not included."
        XCTAssertEqual(AppCopy.text(key, language: .english), key)
        XCTAssertNotEqual(AppCopy.text(key, language: .chinese), key)
        XCTAssertNotEqual(AppCopy.text(key, language: .japanese), key)
        XCTAssertNotEqual(AppCopy.text(key, language: .korean), key)
    }

    func testOverlayWindowPreviewCopyIsLocalized() {
        let keys = [
            "Overlay window preview",
            "Transcript window",
            "Translation window",
            "The current transcription preview appears here.",
            "This example follows the selected window arrangement, confirmed line count, alignment, text styles, background color, and opacity.",
        ]
        for key in keys {
            XCTAssertNotEqual(AppCopy.text(key, language: .chinese), key)
            XCTAssertNotEqual(AppCopy.text(key, language: .japanese), key)
            XCTAssertNotEqual(AppCopy.text(key, language: .korean), key)
        }
    }

    @MainActor
    func testOverlayWindowPreviewRendersCombinedAndSplitLayouts() {
        let suiteName = "OSTTests.overlay-preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(userDefaults: defaults)

        for layout in [OverlayLayout.combined, .split] {
            preferences.overlayLayout = layout
            preferences.overlayLineCount = layout == .combined ? 3 : 10
            for mode in SubtitleDisplayMode.allCases {
                preferences.subtitleDisplayMode = mode
                let renderer = ImageRenderer(content:
                    OverlaySettingsPreview(preferences: preferences)
                        .frame(width: 580)
                        .padding(16)
                )
                renderer.scale = 1
                XCTAssertNotNil(renderer.nsImage, "Could not render \(layout.rawValue), \(mode.rawValue) preview")
            }
        }
    }

    func testMemoryPressureStatusCopyIsLocalized() {
        let key = "Memory pressure — using Apple Translation"
        XCTAssertNotEqual(AppCopy.text(key, language: .chinese), key)
        XCTAssertNotEqual(AppCopy.text(key, language: .japanese), key)
        XCTAssertNotEqual(AppCopy.text(key, language: .korean), key)
    }

    func testAllLiteralAppCopyKeysAreLocalized() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = projectRoot.appendingPathComponent("Sources/OSTApp", isDirectory: true)
        let files = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        )
        let pattern = try NSRegularExpression(
            pattern: #"\b(?:t|text)\("((?:\\.|[^"\\])*)""#
        )
        var keys: Set<String> = []

        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in pattern.matches(in: source, range: range) {
                guard let captureRange = Range(match.range(at: 1), in: source) else { continue }
                let escaped = String(source[captureRange])
                guard !escaped.contains(#"\("#) else { continue }
                let jsonString = "\"" + escaped + "\""
                keys.insert(try JSONDecoder().decode(String.self, from: Data(jsonString.utf8)))
            }
        }

        XCTAssertGreaterThan(keys.count, 100, "Localization source scan did not find the expected UI copy")
        for language in [AppDisplayLanguage.chinese, .japanese, .korean] {
            for key in keys.sorted() {
                XCTAssertNotEqual(
                    AppCopy.text(key, language: language),
                    key,
                    "Missing \(language.rawValue) translation for: \(key)"
                )
            }
        }
    }

    @MainActor
    func testSettingsRequestOpensVisibleWindow() async throws {
        let model = AppModel()
        model.openSettings(tab: .overlay)

        var settingsWindow: NSWindow?
        for _ in 0..<40 {
            settingsWindow = NSApp.windows.first {
                $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
            }
            if settingsWindow?.isVisible == true {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(model.selectedSettingsTab, .overlay)
        XCTAssertNotNil(settingsWindow)
        XCTAssertTrue(settingsWindow?.isVisible == true)
        settingsWindow?.orderOut(nil)
    }

    @MainActor
    func testRepeatedTranslationPackRequestsKeepTheActiveConfiguration() {
        let coordinator = TranslationPackCoordinator()
        coordinator.request(source: .english, target: .korean) {}
        let first = coordinator.configuration

        coordinator.request(source: .english, target: .korean) {}

        XCTAssertEqual(coordinator.configuration, first)
    }
}
