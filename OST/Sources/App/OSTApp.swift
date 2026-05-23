import SwiftUI
@preconcurrency import Translation
import AppKit

@main
struct OSTApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settings = UserSettings()
    @StateObject private var windowManager = WindowManager()
    @State private var activeSourceLanguageSetting: String = "en-US"
    @State private var activeTargetLanguageSetting: String = "ko-KR"
    @State private var activeUseOnDeviceRecognition: Bool = true
    @State private var languageSettingsChangeGeneration: Int = 0
    @State private var captureLifecycleGeneration: Int = 0

    var body: some Scene {
        MenuBarExtra("OST", systemImage: "captions.bubble") {
            MenuBarView(
                appState: appState,
                settings: settings,
                translationService: appState.translationService,
                onToggleCapture: toggleCapture,
                onOpenSettings: openSettings,
                onOpenLogs: { windowManager.showLogViewer() },
                onOpenSessions: { windowManager.showSessionHistory(recorder: appState.sessionRecorder, alwaysOnTop: settings.sessionWindowAlwaysOnTop) },
                onOpenScreenRecordingSettings: openScreenRecordingSettings,
                onOpenSpeechRecognitionSettings: openSpeechRecognitionSettings,
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
        guard !appState.isStartingCapture else { return }
        if appState.isCapturing {
            Task { await stopCapture() }
        } else {
            Task { await startCapture() }
        }
    }

    private func startCapture() async {
        guard appState.beginStartingCapture() else { return }
        captureLifecycleGeneration += 1
        let startGeneration = captureLifecycleGeneration
        defer { appState.finishStartingCapture() }

        appState.clearError()
        appState.onCaptureStoppedWithError = handleCaptureStoppedWithError

        let isAuto = settings.sourceLanguage == "auto"
        let source = selectedSourceLanguage()
        let target = SupportedLanguage(rawValue: settings.targetLanguage) ?? .korean
        AppLogger.shared.log("Configuring: \(isAuto ? "Auto(\(source.displayName))" : source.displayName) → \(target.displayName)", category: .translation)

        // Update speech recognizer language
        await appState.changeSourceLanguage(to: source.speechLocale, useOnDevice: settings.useOnDeviceRecognition)
        guard isCurrentCaptureStart(startGeneration) else {
            appState.translationService.invalidateSession()
            windowManager.hideOverlay()
            return
        }
        guard appState.errorMessage == nil else {
            appState.translationService.invalidateSession()
            windowManager.hideOverlay()
            return
        }
        activeSourceLanguageSetting = settings.sourceLanguage
        activeTargetLanguageSetting = settings.targetLanguage
        activeUseOnDeviceRecognition = settings.useOnDeviceRecognition

        if isAuto {
            appState.enableAutoDetect()
        } else {
            appState.disableAutoDetect()
        }

        // Sync subtitle settings
        appState.updateSubtitleSettings(
            maxLines: settings.safeMaxSubtitleLines,
            expirySeconds: settings.safeSubtitleExpirySeconds,
            pauseSeconds: settings.safeSpeechPauseSeconds
        )
        appState.translationService.setOnlineFallbackEnabled(settings.allowOnlineTranslationFallback)

        // Show overlay first so .translationTask modifier is attached
        windowManager.showOverlay(appState: appState, settings: settings)

        // Give SwiftUI a moment to render the overlay and attach .translationTask,
        // then configure translation — changing config from nil → non-nil triggers the task.
        await prepareTranslationForCurrentSettings(waitForOverlayRender: true)
        guard isCurrentCaptureStart(startGeneration) else {
            appState.translationService.invalidateSession()
            windowManager.hideOverlay()
            return
        }

        await appState.startCapture(saveSession: settings.saveSessionHistory, useOnDevice: settings.useOnDeviceRecognition)
        guard isCurrentCaptureStart(startGeneration) else {
            await appState.stopCapture()
            appState.translationService.invalidateSession()
            windowManager.hideOverlay()
            return
        }
        if appState.errorMessage != nil {
            appState.translationService.invalidateSession()
            windowManager.hideOverlay()
        }
    }

    private func stopCapture() async {
        captureLifecycleGeneration += 1
        languageSettingsChangeGeneration += 1
        await appState.stopCapture()
        appState.translationService.invalidateSession(preservingPendingTranslations: true)
        windowManager.hideOverlay()
    }

    private func openSettings() {
        windowManager.showSettings(
            settings: settings,
            onOpenLogs: { windowManager.showLogViewer() },
            onOpenSessions: { windowManager.showSessionHistory(recorder: appState.sessionRecorder, alwaysOnTop: settings.sessionWindowAlwaysOnTop) },
            onSubtitleSettingsChanged: {
                appState.updateSubtitleSettings(
                    maxLines: settings.safeMaxSubtitleLines,
                    expirySeconds: settings.safeSubtitleExpirySeconds,
                    pauseSeconds: settings.safeSpeechPauseSeconds
                )
            },
            onLanguageSettingsChanged: applyLanguageSettingsWhileCapturing,
            onOnlineFallbackChanged: {
                appState.translationService.setOnlineFallbackEnabled(
                    settings.allowOnlineTranslationFallback,
                    reportPendingStatus: appState.isCapturing
                )
                if appState.isCapturing, settings.allowOnlineTranslationFallback {
                    appState.refreshVisibleTranslationsForLanguageChange()
                }
            },
            onSaveSessionHistoryChanged: {
                appState.updateSessionHistoryRecording(enabled: settings.saveSessionHistory)
            },
            onSessionWindowAlwaysOnTopChanged: {
                windowManager.updateSessionWindowAlwaysOnTop(settings.sessionWindowAlwaysOnTop)
            },
            onDisplayModeChanged: {
                guard appState.isCapturing else { return }
                appState.translationService.invalidateSession()
                windowManager.showOverlay(appState: appState, settings: settings)
                refreshTranslationAfterOverlayChange()
            }
        )
    }

    private func applyLanguageSettingsWhileCapturing() {
        guard appState.isCapturing else { return }
        let requestedSourceLanguage = settings.sourceLanguage
        let requestedTargetLanguage = settings.targetLanguage
        let requestedUseOnDeviceRecognition = settings.useOnDeviceRecognition
        languageSettingsChangeGeneration += 1
        let changeGeneration = languageSettingsChangeGeneration

        Task {
            let isAuto = requestedSourceLanguage == "auto"
            let source = selectedSourceLanguage(for: requestedSourceLanguage)

            let recognitionSettingChanged = requestedSourceLanguage != activeSourceLanguageSetting
                || requestedUseOnDeviceRecognition != activeUseOnDeviceRecognition
            let sourceSettingChanged = requestedSourceLanguage != activeSourceLanguageSetting
            let switchedToAutoSource = sourceSettingChanged && isAuto
            let translationSettingChanged = requestedSourceLanguage != activeSourceLanguageSetting
                || requestedTargetLanguage != activeTargetLanguageSetting

            if recognitionSettingChanged {
                if sourceSettingChanged && !isAuto {
                    appState.disableAutoDetect()
                }
                await appState.changeSourceLanguage(to: source.speechLocale, useOnDevice: requestedUseOnDeviceRecognition)
                guard appState.errorMessage == nil else {
                    appState.translationService.invalidateSession()
                    windowManager.hideOverlay()
                    return
                }
                guard isCurrentLanguageSettingsChange(changeGeneration) else {
                    applyLanguageSettingsWhileCapturing()
                    return
                }
                activeSourceLanguageSetting = requestedSourceLanguage
                activeUseOnDeviceRecognition = requestedUseOnDeviceRecognition

                if switchedToAutoSource {
                    appState.enableAutoDetect()
                }
            }
            if translationSettingChanged {
                appState.translationService.invalidateSession()
                appState.clearVisibleTranslationsForLanguageChange()
                await prepareTranslationForCurrentSettings(
                    sourceLanguageSetting: requestedSourceLanguage,
                    targetLanguageSetting: requestedTargetLanguage,
                    waitForOverlayRender: false
                )
                guard isCurrentLanguageSettingsChange(changeGeneration) else {
                    applyLanguageSettingsWhileCapturing()
                    return
                }
                appState.refreshVisibleTranslationsForLanguageChange()
            }
            guard isCurrentLanguageSettingsChange(changeGeneration) else {
                applyLanguageSettingsWhileCapturing()
                return
            }
            activeSourceLanguageSetting = requestedSourceLanguage
            activeTargetLanguageSetting = requestedTargetLanguage
        }
    }

    private func refreshTranslationAfterOverlayChange() {
        languageSettingsChangeGeneration += 1
        let changeGeneration = languageSettingsChangeGeneration
        Task {
            await prepareTranslationForCurrentSettings(waitForOverlayRender: true)
            guard isCurrentLanguageSettingsChange(changeGeneration) else { return }
            appState.refreshVisibleTranslationsForLanguageChange()
        }
    }

    private func isCurrentLanguageSettingsChange(_ generation: Int) -> Bool {
        appState.isCapturing && generation == languageSettingsChangeGeneration
    }

    private func isCurrentCaptureStart(_ generation: Int) -> Bool {
        generation == captureLifecycleGeneration
    }

    private func handleCaptureStoppedWithError() {
        guard appState.errorMessage != nil else { return }
        captureLifecycleGeneration += 1
        languageSettingsChangeGeneration += 1
        appState.translationService.invalidateSession(preservingPendingTranslations: true)
        windowManager.hideOverlay()
    }

    private func prepareTranslationForCurrentSettings(
        sourceLanguageSetting: String? = nil,
        targetLanguageSetting: String? = nil,
        waitForOverlayRender: Bool
    ) async {
        if waitForOverlayRender {
            try? await Task.sleep(for: .milliseconds(200))
        }

        let source = selectedSourceLanguage(for: sourceLanguageSetting ?? settings.sourceLanguage)
        let target = SupportedLanguage(rawValue: targetLanguageSetting ?? settings.targetLanguage) ?? .korean
        appState.translationService.configure(
            source: source.translationLocale,
            target: target.translationLocale
        )
        _ = await appState.translationService.waitForSessionReady(timeout: 1.0)
    }

    private func openScreenRecordingSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func openSpeechRecognitionSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
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

    private func selectedSourceLanguage() -> SupportedLanguage {
        selectedSourceLanguage(for: settings.sourceLanguage)
    }

    private func selectedSourceLanguage(for sourceLanguageSetting: String) -> SupportedLanguage {
        if sourceLanguageSetting == "auto" {
            if appState.isCapturing, let detected = appState.detectedLanguage {
                return detected
            }
            return systemLanguageOrDefault()
        }
        return SupportedLanguage(rawValue: sourceLanguageSetting) ?? .english
    }

    private func quitApp() {
        Task {
            await stopCapture()
            NSApplication.shared.terminate(nil)
        }
    }
}
