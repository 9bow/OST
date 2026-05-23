import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: UserSettings
    let onOpenLogs: () -> Void
    let onOpenSessions: () -> Void
    var onResetOverlay: (() -> Void)?
    var onResetOverlay2: (() -> Void)?
    var onToggleOverlayLock: ((Bool) -> Void)?
    var onToggleOverlay2Lock: ((Bool) -> Void)?
    var onSubtitleSettingsChanged: (() -> Void)?
    var onLanguageSettingsChanged: (() -> Void)?
    var onOnlineFallbackChanged: (() -> Void)?
    var onSaveSessionHistoryChanged: (() -> Void)?
    var onSessionWindowAlwaysOnTopChanged: (() -> Void)?
    var onDisplayModeChanged: (() -> Void)?

    var body: some View {
        TabView {
            FontSettingsView(
                settings: settings,
                onResetOverlay: onResetOverlay,
                onResetOverlay2: onResetOverlay2,
                onToggleOverlayLock: onToggleOverlayLock,
                onToggleOverlay2Lock: onToggleOverlay2Lock,
                onSubtitleSettingsChanged: onSubtitleSettingsChanged,
                onDisplayModeChanged: onDisplayModeChanged
            )
                .tabItem {
                    Label("Display", systemImage: "textformat.size")
                }

            LanguagePickerView(
                settings: settings,
                onLanguageSettingsChanged: onLanguageSettingsChanged,
                onOnlineFallbackChanged: onOnlineFallbackChanged
            )
                .tabItem {
                    Label("Languages", systemImage: "globe")
                }

            DebugSettingsView(
                settings: settings,
                onOpenLogs: onOpenLogs,
                onOpenSessions: onOpenSessions,
                onSaveSessionHistoryChanged: onSaveSessionHistoryChanged,
                onSessionWindowAlwaysOnTopChanged: onSessionWindowAlwaysOnTopChanged
            )
            .tabItem {
                Label("Debug", systemImage: "ladybug")
            }

            PrerequisitesView()
                .tabItem {
                    Label("Setup", systemImage: "checklist")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - Debug Settings

private struct DebugSettingsView: View {
    @ObservedObject var settings: UserSettings
    let onOpenLogs: () -> Void
    let onOpenSessions: () -> Void
    var onSaveSessionHistoryChanged: (() -> Void)?
    var onSessionWindowAlwaysOnTopChanged: (() -> Void)?

    var body: some View {
        Form {
            Section("Session Recording") {
                Toggle("Save session history", isOn: saveSessionHistoryBinding)
                    .accessibilityLabel("Save session history toggle")
                    .accessibilityHint("When enabled, recognized and translated text is saved per session")

                Toggle("Session window always on top", isOn: sessionWindowAlwaysOnTopBinding)
                    .accessibilityLabel("Session window always on top")
            }

            Section("Actions") {
                Button("View Logs") { onOpenLogs() }
                    .accessibilityLabel("Open log viewer window")

                Button("Session History") { onOpenSessions() }
                    .accessibilityLabel("Open session history window")
            }
        }
        .formStyle(.grouped)
    }

    private var saveSessionHistoryBinding: Binding<Bool> {
        Binding(
            get: { settings.saveSessionHistory },
            set: { newValue in
                settings.saveSessionHistory = newValue
                onSaveSessionHistoryChanged?()
            }
        )
    }

    private var sessionWindowAlwaysOnTopBinding: Binding<Bool> {
        Binding(
            get: { settings.sessionWindowAlwaysOnTop },
            set: { newValue in
                settings.sessionWindowAlwaysOnTop = newValue
                onSessionWindowAlwaysOnTopChanged?()
            }
        )
    }
}

// MARK: - Prerequisites Tab

private struct PrerequisitesView: View {
    var body: some View {
        Form {
            Section("Required Permissions") {
                prerequisiteRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    description: "Required for system audio capture via ScreenCaptureKit.",
                    action: "System Settings > Privacy & Security > Screen & System Audio Recording",
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                )

                prerequisiteRow(
                    icon: "speaker.wave.2",
                    title: "System Audio Recording",
                    description: "Required for system audio capture on macOS 15 or later.",
                    action: "System Settings > Privacy & Security > Screen & System Audio Recording",
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                )

                prerequisiteRow(
                    icon: "mic.badge.plus",
                    title: "Speech Recognition",
                    description: "Required for SFSpeechRecognizer to transcribe audio.",
                    action: "System Settings > Privacy & Security > Speech Recognition",
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
                )
            }

            Section("Recommended Setup") {
                prerequisiteRow(
                    icon: "arrow.down.circle",
                    title: "On-Device Speech Model",
                    description: "Download the speech model for your source language for faster, offline transcription.",
                    action: "System Settings > Keyboard > Dictation > Languages",
                    url: "x-apple.systempreferences:com.apple.preference.keyboard"
                )

                prerequisiteRow(
                    icon: "globe",
                    title: "Translation Language Pack",
                    description: "Download translation language packs for offline translation.",
                    action: "System Settings > General > Language & Region > Translation Languages",
                    url: "x-apple.systempreferences:com.apple.Localization-Settings"
                )
            }

            Section("Notes") {
                Text("• macOS 15.0 (Sequoia) or later is required.")
                    .font(.caption)
                Text("• On first launch, macOS may prompt for Screen Recording, System Audio Recording, and Speech Recognition permissions.")
                    .font(.caption)
                Text("• If on-device speech model is not available, server-based transcription is used (requires internet).")
                    .font(.caption)
                Text("• Online translation fallback is only used when enabled in Languages.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func prerequisiteRow(icon: String, title: String, description: String, action: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                    .fontWeight(.medium)
            }
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
            Button(action) {
                if let url = URL(string: url) {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption)
            .buttonStyle(.link)
        }
    }
}

// MARK: - About Tab

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
                .accessibilityLabel("OST app icon")

            Text("OST — On-Screen Translator")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Real-time speech transcription and translation overlay.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("macOS 15.0+")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
