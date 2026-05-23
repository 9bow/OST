import SwiftUI
@preconcurrency import Translation

struct SubtitleView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: UserSettings
    @ObservedObject var translationService: TranslationService

    @State private var isAtBottom = true

    var body: some View {
        let generation = translationService.configurationGeneration

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: !settings.overlayLocked) {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 0)

                    ForEach(appState.subtitleEntries) { entry in
                        subtitleRow(entry)
                            .transition(.opacity)
                    }

                    if !appState.liveText.isEmpty && settings.showOriginalText {
                        Text(appState.liveText)
                            .font(.system(size: settings.safeFontSize))
                            .foregroundColor(settings.fontColor.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !appState.liveTranslatedText.isEmpty && settings.showTranslation {
                        Text(appState.liveTranslatedText)
                            .font(.system(size: settings.safeTranslatedFontSize))
                            .foregroundColor(settings.translatedFontColor.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if settings.showTranslation, let message = translationStatusText {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.orange.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Color.clear
                        .frame(height: 16)
                        .id("bottom")
                }
                .frame(maxWidth: .infinity, minHeight: 0, alignment: .bottomLeading)
            }
            .scrollDisabled(settings.overlayLocked)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let atBottom = geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 10
                return atBottom
            } action: { _, newValue in
                isAtBottom = newValue
            }
            .onChange(of: appState.subtitleEntries.map(\.id)) { _, _ in
                if isAtBottom || settings.overlayLocked {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .onChange(of: appState.liveText) { _, _ in
                if isAtBottom || settings.overlayLocked {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .onChange(of: appState.liveTranslatedText) { _, _ in
                if isAtBottom || settings.overlayLocked {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .onChange(of: appState.subtitleEntries.map(\.translated)) { _, _ in
                if isAtBottom || settings.overlayLocked {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(settings.backgroundColor.opacity(settings.safeBackgroundOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    settings.overlayLocked
                        ? Color.white.opacity(0.15)
                        : Color.accentColor.opacity(0.6),
                    lineWidth: settings.overlayLocked ? 1 : 2
                )
        )
        .animation(.easeInOut(duration: 0.2), value: appState.subtitleEntries.map(\.id))
        .translationTask(translationService.configuration) { session in
            AppLogger.shared.log("Translation session delivered by .translationTask", category: .translation)
            translationService.handleSession(session, generation: generation)
        }
    }

    @ViewBuilder
    private func subtitleRow(_ entry: SubtitleEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if settings.showOriginalText {
                Text(entry.recognized)
                    .font(.system(size: settings.safeFontSize))
                    .foregroundColor(settings.fontColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if settings.showTranslation {
                Text(entry.translated.isEmpty ? "..." : entry.translated)
                    .font(.system(size: settings.safeTranslatedFontSize))
                    .foregroundColor(entry.translated.isEmpty
                        ? settings.translatedFontColor.opacity(0.4)
                        : settings.translatedFontColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var translationStatusText: String? {
        if let error = translationService.lastErrorMessage, !error.isEmpty {
            return error
        }
        if let status = translationService.statusMessage, !status.isEmpty {
            return status
        }
        return nil
    }
}
