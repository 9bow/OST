import SwiftUI
import Translation

@main
struct OSTApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settings = UserSettings()
    @StateObject private var windowManager = WindowManager()

    var body: some Scene {
        MenuBarExtra("OST", systemImage: "captions.bubble") {
            MenuBarView(
                appState: appState,
                settings: settings,
                onToggleCapture: toggleCapture,
                onOpenSettings: openSettings,
                onOpenLogs: { windowManager.showLogViewer() },
                onOpenSessions: { windowManager.showSessionHistory(recorder: appState.sessionRecorder, alwaysOnTop: settings.sessionWindowAlwaysOnTop) },
                onToggleOverlayLock: { locked in
                    windowManager.updateOverlayLock(locked: locked)
                    if settings.overlayDisplayMode == "split" {
                        settings.overlay2Locked = locked
                        windowManager.updateOverlay2Lock(locked: locked)
                    }
                },
                onQuit: quitApp
            )
        }
    }

    // MARK: - Actions

    private func toggleCapture() {
        if appState.isCapturing {
            Task { await stopCapture() }
        } else {
            Task { await startCapture() }
        }
    }

    private func startCapture() async {
        let isAuto = settings.sourceLanguage == "auto"
        let source = isAuto ? systemLanguageOrDefault() : (SupportedLanguage(rawValue: settings.sourceLanguage) ?? .english)
        let target = SupportedLanguage(rawValue: settings.targetLanguage) ?? .korean
        AppLogger.shared.log("Configuring: \(isAuto ? "Auto(\(source.displayName))" : source.displayName) → \(target.displayName)", category: .translation)

        // Update speech recognizer language
        await appState.changeSourceLanguage(to: source.speechLocale, useOnDevice: settings.useOnDeviceRecognition)

        if isAuto {
            appState.enableAutoDetect()
        }

        // Sync subtitle settings
        appState.maxSubtitleLines = Int(settings.maxSubtitleLines)
        appState.subtitleExpirySeconds = settings.subtitleExpirySeconds
        appState.speechPauseSeconds = settings.speechPauseSeconds

        // Show overlay first so .translationTask modifier is attached
        windowManager.showOverlay(appState: appState, settings: settings)

        // Give SwiftUI a moment to render SubtitleView and attach .translationTask,
        // then configure translation — changing config from nil → non-nil triggers the task.
        try? await Task.sleep(for: .milliseconds(200))
        appState.translationService.configure(
            source: source.translationLocale,
            target: target.translationLocale
        )

        await appState.startCapture(saveSession: settings.saveSessionHistory, useOnDevice: settings.useOnDeviceRecognition)
        if appState.errorMessage != nil {
            windowManager.hideOverlay()
        }
    }

    private func stopCapture() async {
        await appState.stopCapture()
        windowManager.hideOverlay()
    }

    private func openSettings() {
        windowManager.showSettings(
            settings: settings,
            onOpenLogs: { windowManager.showLogViewer() },
            onOpenSessions: { windowManager.showSessionHistory(recorder: appState.sessionRecorder, alwaysOnTop: settings.sessionWindowAlwaysOnTop) }
        )
    }

    private func systemLanguageOrDefault() -> SupportedLanguage {
        let langCode = Locale.current.language.languageCode?.identifier ?? "en"
        switch langCode {
        case "ko": return .korean
        case "ja": return .japanese
        case "zh": return .chineseSimplified
        default: return .english
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
