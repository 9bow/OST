import OSTCore
import SwiftUI

@MainActor
struct OverlaySettingsPreview: View {
    @ObservedObject var preferences: PreferencesStore
    @StateObject private var state = OverlayState()

    private let designWidth: CGFloat = 720
    private let previewWidth: CGFloat = 540

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if preferences.overlayLayout == .combined {
                panel(kind: .combined, maximumPreviewHeight: 320)
            } else {
                if preferences.subtitleDisplayMode.showsSource {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("Transcript window"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        panel(kind: .source, maximumPreviewHeight: 180)
                    }
                }
                if preferences.subtitleDisplayMode.showsTranslation {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("Translation window"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        panel(kind: .translation, maximumPreviewHeight: 180)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: updateSampleSegments)
        .onChange(of: preferences.appDisplayLanguage) { _, _ in
            updateSampleSegments()
        }
        .onChange(of: preferences.microphoneMode) { _, _ in
            updateSampleSegments()
        }
    }

    private func panel(
        kind: OverlayPanelKind,
        maximumPreviewHeight: CGFloat
    ) -> some View {
        let designSize = preferredSize(for: kind)
        let scale = min(
            previewWidth / designWidth,
            maximumPreviewHeight / designSize.height
        )
        let displayedSize = CGSize(
            width: designSize.width * scale,
            height: designSize.height * scale
        )

        return OverlayContentView(
            kind: kind,
            state: state,
            preferences: preferences,
            isSettingsPreview: true
        )
        .frame(width: designSize.width, height: designSize.height)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(
            width: displayedSize.width,
            height: displayedSize.height,
            alignment: .topLeading
        )
        .accessibilityLabel(t("Overlay window preview"))
    }

    private func preferredSize(for kind: OverlayPanelKind) -> CGSize {
        switch kind {
        case .combined:
            return OverlaySizing.combinedSize(
                lineCount: preferences.overlayLineCount,
                sourceFontSize: preferences.sourceFontSize,
                translationFontSize: preferences.translationFontSize,
                previewFontSize: preferences.previewFontSize,
                displayMode: preferences.subtitleDisplayMode,
                microphoneMode: state.microphoneMode ?? preferences.microphoneMode,
                maximumHeight: 2_000
            )
        case .source:
            return OverlaySizing.sourceSize(
                lineCount: preferences.overlayLineCount,
                fontSize: preferences.sourceFontSize,
                microphoneMode: state.microphoneMode ?? preferences.microphoneMode,
                maximumHeight: 2_000
            )
        case .translation:
            return OverlaySizing.translationSize(
                lineCount: preferences.overlayLineCount,
                fontSize: preferences.translationFontSize,
                previewFontSize: preferences.previewFontSize,
                microphoneMode: state.microphoneMode ?? preferences.microphoneMode,
                maximumHeight: 2_000
            )
        }
    }

    private func updateSampleSegments() {
        let language: SupportedLanguage
        switch preferences.sourceMode {
        case .fixed(let selected): language = selected
        case .automatic: language = .english
        }
        state.isListening = true
        state.microphoneMode = preferences.microphoneMode
        state.segments = [
            TranscriptSegment(
                id: UUID(uuidString: "0F3B783B-240B-4C32-909D-677560703DBB")!,
                startTime: .zero,
                endTime: .seconds(2),
                language: language,
                sourceText: t("Transcription results appear here."),
                translatedText: t("Confirmed translation results appear here."),
                isFinal: true
            ),
            TranscriptSegment(
                id: UUID(uuidString: "C67548FC-546E-42F6-8491-A5F65B0E280B")!,
                startTime: .seconds(2),
                language: language,
                sourceText: t("The current transcription preview appears here."),
                translatedText: t("The current translation preview appears here."),
                isFinal: false
            ),
        ]
        if preferences.microphoneMode.isEnabled {
            state.segments.insert(TranscriptSegment(
                id: UUID(uuidString: "A2D8F4D5-4199-4C55-B9CC-8B0FBBA74D27")!,
                startTime: .seconds(1),
                endTime: .seconds(2),
                language: language,
                sourceText: t("Microphone subtitles appear here."),
                translatedText: preferences.microphoneMode == .transcriptionAndTranslation
                    ? t("Microphone subtitles appear here.") : nil,
                isFinal: true,
                audioSource: .microphone
            ), at: 1)
            state.segments.append(TranscriptSegment(
                id: UUID(uuidString: "DC0E04B8-165F-4186-8370-7E0B68CC09EC")!,
                startTime: .seconds(2),
                language: language,
                sourceText: t("Microphone subtitles appear here."),
                translatedText: preferences.microphoneMode == .transcriptionAndTranslation
                    ? t("Microphone subtitles appear here.") : nil,
                isFinal: false,
                audioSource: .microphone
            ))
        }
    }

    private func t(_ english: String) -> String {
        AppCopy.text(english, language: preferences.appDisplayLanguage)
    }
}
