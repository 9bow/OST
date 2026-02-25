import SwiftUI
import Translation

struct SubtitleView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: UserSettings
    @ObservedObject var translationService: TranslationService

    @State private var isAtBottom = true

    var body: some View {
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
                            .font(.system(size: settings.fontSize))
                            .foregroundColor(settings.fontColor.opacity(0.6))
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
            .onChange(of: appState.subtitleEntries.count) { _, _ in
                if isAtBottom || settings.overlayLocked {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .onChange(of: appState.liveText) { _, _ in
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
