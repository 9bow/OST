import SwiftUI
import Translation

struct SubtitleView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: UserSettings
    @ObservedObject var translationService: TranslationService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)

            ForEach(appState.subtitleEntries) { entry in
                subtitleRow(entry)
                    .transition(.opacity)
            }

            if !appState.liveText.isEmpty && settings.showOriginalText {
                Text(appState.liveText)
                    .font(.system(size: settings.fontSize))
                    .foregroundColor(settings.fontColor.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(settings.backgroundColor.opacity(settings.backgroundOpacity))
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
        .animation(.easeInOut(duration: 0.2), value: appState.subtitleEntries.count)
        .translationTask(translationService.configuration) { session in
            AppLogger.shared.log("Translation session delivered by .translationTask", category: .translation)
            translationService.handleSession(session)
        }
    }

    @ViewBuilder
    private func subtitleRow(_ entry: SubtitleEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if settings.showOriginalText {
                Text(entry.recognized)
                    .font(.system(size: settings.fontSize))
                    .foregroundColor(settings.fontColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if settings.showTranslation && !entry.translated.isEmpty {
                Text(entry.translated)
                    .font(.system(size: settings.translatedFontSize))
                    .foregroundColor(settings.translatedFontColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
