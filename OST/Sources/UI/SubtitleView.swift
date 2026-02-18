import SwiftUI
import Translation

struct SubtitleView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: UserSettings
    @ObservedObject var translationService: TranslationService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(appState.subtitleEntries) { entry in
                subtitleRow(entry)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
            }

            // Show live partial text (not yet finalized)
            if !appState.liveText.isEmpty {
                if settings.showOriginalText {
                    Text(appState.liveText)
                        .font(.system(size: settings.fontSize))
                        .foregroundColor(settings.fontColor.opacity(0.6))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(settings.backgroundColor.opacity(settings.backgroundOpacity))
        )
        .animation(.easeInOut(duration: 0.2), value: appState.subtitleEntries.count)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
