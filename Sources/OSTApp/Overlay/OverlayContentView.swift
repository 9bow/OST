import SwiftUI
import OSTCore

enum OverlayPanelKind: Hashable {
    case combined
    case source
    case translation
}

struct OverlayContentView: View {
    let kind: OverlayPanelKind
    @ObservedObject var state: OverlayState
    @ObservedObject var preferences: PreferencesStore
    let isSettingsPreview: Bool

    init(
        kind: OverlayPanelKind,
        state: OverlayState,
        preferences: PreferencesStore,
        isSettingsPreview: Bool = false
    ) {
        self.kind = kind
        self.state = state
        self.preferences = preferences
        self.isSettingsPreview = isSettingsPreview
    }

    var body: some View {
        draggableContent
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minWidth: 320, minHeight: 96)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                if !preferences.overlayLocked, !isSettingsPreview {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    @ViewBuilder
    private var draggableContent: some View {
        if preferences.overlayLocked || isSettingsPreview {
            content
        } else {
            content
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .combined:
            VStack(alignment: preferences.subtitleAlignment.horizontalAlignment, spacing: 8) {
                if preferences.subtitleDisplayMode.showsSource {
                    sourceText
                }
                if preferences.subtitleDisplayMode == .both {
                    Divider().overlay(.white.opacity(0.12))
                }
                if preferences.subtitleDisplayMode.showsTranslation {
                    translationText
                }
            }
        case .source:
            sourceText
        case .translation:
            translationText
        }
    }

    private var sourceText: some View {
        LatestSubtitleView(
            segments: state.segments,
            track: .source,
            placeholder: t("Choose Start from the OST menu bar icon.\nTranscription results appear here."),
            font: .system(size: preferences.sourceFontSize, weight: .regular),
            foregroundColor: color(preferences.sourceColor),
            liveFont: .system(size: preferences.sourceFontSize, weight: .regular),
            liveForegroundColor: color(preferences.sourceColor),
            microphoneColor: color(preferences.microphoneColor),
            microphoneEnabled: (state.microphoneMode ?? preferences.microphoneMode).isEnabled,
            microphoneLabel: t("Microphone"),
            alignment: preferences.subtitleAlignment,
            showsPlaceholder: !state.isListening
        )
    }

    private var translationText: some View {
        LatestSubtitleView(
            segments: state.segments,
            track: .translation,
            placeholder: t("Choose Start from the OST menu bar icon.\nTranslation results appear here."),
            font: .system(size: preferences.translationFontSize, weight: .semibold),
            foregroundColor: color(preferences.translationColor),
            liveFont: .system(size: preferences.previewFontSize, weight: .semibold),
            liveForegroundColor: color(preferences.previewColor),
            microphoneColor: color(preferences.microphoneColor),
            microphoneEnabled: (state.microphoneMode ?? preferences.microphoneMode) == .transcriptionAndTranslation,
            microphoneLabel: t("Microphone"),
            alignment: preferences.subtitleAlignment,
            showsPlaceholder: !state.isListening
        )
    }

    private var backgroundColor: Color {
        let value = preferences.backgroundColor
        return Color(
            red: value.red,
            green: value.green,
            blue: value.blue,
            opacity: value.alpha * preferences.backgroundOpacity
        )
    }

    private func color(_ value: RGBAColor) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }

    private func t(_ english: String) -> String {
        AppCopy.text(english, language: preferences.appDisplayLanguage)
    }
}

private enum SubtitleTrack: Equatable {
    case source
    case translation

    func text(from segment: TranscriptSegment) -> String? {
        switch self {
        case .source:
            return segment.sourceText.isEmpty ? nil : segment.sourceText
        case .translation:
            guard let text = segment.translatedText, !text.isEmpty else { return nil }
            return text
        }
    }
}

private struct LatestSubtitleView: View {
    private struct Entry: Identifiable {
        let segment: TranscriptSegment
        let text: String
        var id: UUID { segment.id }
    }

    let segments: [TranscriptSegment]
    let track: SubtitleTrack
    let placeholder: String
    let font: Font
    let foregroundColor: Color
    let liveFont: Font
    let liveForegroundColor: Color
    let microphoneColor: Color
    let microphoneEnabled: Bool
    let microphoneLabel: String
    let alignment: SubtitleAlignment
    let showsPlaceholder: Bool

    private let bottomID = "OSTSubtitleBottom"

    private var entries: [Entry] {
        DisplaySegmentGrouper.group(segments).compactMap { segment in
            track.text(from: segment).map { Entry(segment: segment, text: $0) }
        }
    }

    private var stableEntries: [Entry] {
        entries.filter(\.segment.isFinal)
    }

    private var liveEntries: [Entry] {
        entries.filter { !$0.segment.isFinal }
    }

    private var liveAccessibilityLabel: String {
        switch track {
        case .source: "Current transcription"
        case .translation: "Current translation preview"
        }
    }

    private var revision: String {
        stableEntries.map { entry in
            "\(entry.segment.id.uuidString):\(entry.segment.isFinal):\(entry.text)"
        }.joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: alignment.horizontalAlignment, spacing: 5) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    if stableEntries.isEmpty {
                        if liveEntries.isEmpty, showsPlaceholder {
                            Text(placeholder)
                                .opacity(0.7)
                                .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
                        }
                    } else {
                        LazyVStack(alignment: alignment.horizontalAlignment, spacing: 5) {
                            ForEach(stableEntries) { entry in
                                subtitle(entry.text, source: entry.segment.audioSource)
                                    .foregroundStyle(entry.segment.audioSource == .microphone ? microphoneColor : foregroundColor)
                                    .accessibilityLabel(entry.segment.audioSource == .microphone ? "\(microphoneLabel): \(entry.text)" : entry.text)
                                    .opacity(entry.id == stableEntries.last?.id ? 1 : 0.72)
                                    .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(bottomID)
                        }
                    }
                }
                .font(font)
                .foregroundStyle(foregroundColor)
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.hidden)
                .onAppear { scrollToLatest(using: proxy) }
                .onChange(of: revision) { _, _ in scrollToLatest(using: proxy) }
            }
            ForEach(AudioSource.allCases.filter { $0 == .systemAudio || microphoneEnabled }, id: \.self) { source in
                let entry = liveEntries.last { $0.segment.audioSource == source }
                subtitle(entry?.text ?? " ", source: source)
                    .font(liveFont)
                    .foregroundStyle(source == .microphone ? microphoneColor : liveForegroundColor)
                    .opacity(entry == nil ? 0 : 0.9)
                    .lineLimit(OverlaySizing.previewLineCount, reservesSpace: true)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
                    .accessibilityHidden(entry == nil)
                    .accessibilityLabel("\(source == .microphone ? microphoneLabel : liveAccessibilityLabel): \(entry?.text ?? "")")
            }
        }
        .multilineTextAlignment(alignment.textAlignment)
        .lineSpacing(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard !stableEntries.isEmpty else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }

    private func subtitle(_ text: String, source: AudioSource) -> Text {
        source == .microphone
            ? Text("\(Image(systemName: "mic.fill")) \(text)")
            : Text(text)
    }
}

private extension SubtitleAlignment {
    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
