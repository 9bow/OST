import SwiftUI
import Translation

/// Overlay view for split mode: shows only translated text.
/// Hosts the .translationTask modifier to receive translation sessions.
struct TranslationOverlayView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: UserSettings
    @ObservedObject var translationService: TranslationService

    @State private var isAtBottom = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: !settings.overlay2Locked) {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 0)

                    ForEach(appState.subtitleEntries) { entry in
                        Text(entry.translated.isEmpty ? "..." : entry.translated)
                            .font(.system(size: settings.translatedFontSize))
                            .foregroundColor(entry.translated.isEmpty
                                ? settings.translatedFontColor.opacity(0.4)
                                : settings.translatedFontColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }

                    if !appState.liveTranslatedText.isEmpty {
                        Text(appState.liveTranslatedText)
                            .font(.system(size: settings.translatedFontSize))
                            .foregroundColor(settings.translatedFontColor.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Color.clear
                        .frame(height: 16)
                        .id("bottom")
                }
                .frame(maxWidth: .infinity, minHeight: 0, alignment: .bottomLeading)
            }
            .scrollDisabled(settings.overlay2Locked)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let atBottom = geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 10
                return atBottom
            } action: { _, newValue in
                isAtBottom = newValue
            }
            .onChange(of: appState.subtitleEntries.count) { _, _ in
                if isAtBottom || settings.overlay2Locked {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .onChange(of: appState.liveTranslatedText) { _, _ in
                if isAtBottom || settings.overlay2Locked {
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
                    settings.overlay2Locked
                        ? Color.white.opacity(0.15)
                        : Color.accentColor.opacity(0.6),
                    lineWidth: settings.overlay2Locked ? 1 : 2
                )
        )
        .animation(.easeInOut(duration: 0.2), value: appState.subtitleEntries.count)
        .translationTask(translationService.configuration) { session in
            AppLogger.shared.log("Translation session delivered by .translationTask", category: .translation)
            translationService.handleSession(session)
        }
    }
}
