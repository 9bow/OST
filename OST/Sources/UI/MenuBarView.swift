import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: UserSettings
    @ObservedObject var translationService: TranslationService

    let onToggleCapture: () -> Void
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void
    let onOpenSessions: () -> Void
    let onOpenScreenRecordingSettings: () -> Void
    let onOpenSpeechRecognitionSettings: () -> Void
    let onToggleOverlayLock: (Bool) -> Void
    let onQuit: () -> Void

    private var sourceLanguageDisplay: String {
        if settings.sourceLanguage == "auto" {
            guard let detectedSourceLanguage else { return "Auto" }
            return "Auto (\(detectedSourceLanguage.displayName))"
        }
        return (SupportedLanguage(rawValue: settings.sourceLanguage) ?? .english).displayName
    }

    private var sourceLanguageIcon: String {
        if settings.sourceLanguage == "auto" {
            return detectedSourceLanguage?.flagEmoji ?? "🌐"
        }
        return sourceLanguage.flagEmoji
    }

    private var detectedSourceLanguage: SupportedLanguage? {
        appState.detectedLanguage
    }

    private var sourceLanguage: SupportedLanguage {
        SupportedLanguage(rawValue: settings.sourceLanguage) ?? .english
    }

    private var targetLanguage: SupportedLanguage {
        SupportedLanguage(rawValue: settings.targetLanguage) ?? .korean
    }

    var body: some View {
        Group {
            Text("Status: \(statusText)")
                .accessibilityLabel("Status: \(statusText)")

            if let error = appState.errorMessage, !error.isEmpty {
                Text(error)
                    .accessibilityLabel("Error: \(error)")

                if let recovery = errorRecovery {
                    Button(recovery.title) {
                        switch recovery {
                        case .screenRecording:
                            onOpenScreenRecordingSettings()
                        case .speechRecognition:
                            onOpenSpeechRecognitionSettings()
                        }
                    }
                }
            }

            if let message = translationStatusText {
                Text("Translation: \(message)")
                    .accessibilityLabel("Translation status: \(message)")
            }

            Divider()

            Text("\(sourceLanguageIcon) \(sourceLanguageDisplay) → \(targetLanguage.flagEmoji) \(targetLanguage.displayName)")
                .accessibilityLabel("Translating from \(sourceLanguageDisplay) to \(targetLanguage.displayName)")

            Divider()

            Button(captureButtonTitle, action: onToggleCapture)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.isStartingCapture)
                .accessibilityLabel(captureButtonTitle)

            Button("Settings...", action: onOpenSettings)
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityLabel("Open settings")

            Divider()

            Toggle("Lock Overlay", isOn: Binding(
                get: { settings.overlayLocked },
                set: { newValue in
                    settings.overlayLocked = newValue
                    onToggleOverlayLock(newValue)
                }
            ))
                .accessibilityLabel("Lock overlay position")

            Divider()

            Button("Debug Console", action: onOpenLogs)
                .accessibilityLabel("Open debug console")

            Button("Session History", action: onOpenSessions)
                .accessibilityLabel("Open session history")

            Divider()

            Button("Quit OST", action: onQuit)
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityLabel("Quit OST")
        }
    }

    // MARK: - Helpers

    private var statusText: String {
        if appState.errorMessage != nil {
            return "Error"
        }
        if appState.isStartingCapture {
            return "Starting"
        }
        return appState.isCapturing ? "Capturing" : "Idle"
    }

    private var captureButtonTitle: String {
        if appState.isStartingCapture { return "Starting Capture..." }
        return appState.isCapturing ? "Stop Capture" : "Start Capture"
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

    private var errorRecovery: ErrorRecovery? {
        guard let message = appState.errorMessage?.lowercased() else { return nil }
        if message.contains("screen recording") || message.contains("system audio recording") {
            return .screenRecording
        }
        if message.contains("speech recognition") {
            return .speechRecognition
        }
        return nil
    }
}

private enum ErrorRecovery {
    case screenRecording
    case speechRecognition

    var title: String {
        switch self {
        case .screenRecording:
            return "Open Screen & System Audio Recording Settings"
        case .speechRecognition:
            return "Open Speech Recognition Settings"
        }
    }
}
