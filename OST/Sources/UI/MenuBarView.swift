import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: UserSettings

    let onToggleCapture: () -> Void
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void
    let onOpenSessions: () -> Void
    let onToggleOverlayLock: (Bool) -> Void
    let onQuit: () -> Void

    private var sourceLanguageDisplay: String {
        if settings.sourceLanguage == "auto" { return "Auto" }
        return (SupportedLanguage(rawValue: settings.sourceLanguage) ?? .english).displayName
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
            }

            Divider()

            Text("\(settings.sourceLanguage == "auto" ? "🌐" : sourceLanguage.flagEmoji) \(sourceLanguageDisplay) → \(targetLanguage.flagEmoji) \(targetLanguage.displayName)")
                .accessibilityLabel("Translating from \(sourceLanguageDisplay) to \(targetLanguage.displayName)")

            Divider()

            Button(appState.isCapturing ? "Stop Capture" : "Start Capture", action: onToggleCapture)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel(appState.isCapturing ? "Stop capturing audio" : "Start capturing audio")

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
        return appState.isCapturing ? "Capturing" : "Idle"
    }
}
