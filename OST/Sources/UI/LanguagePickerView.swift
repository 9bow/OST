import SwiftUI
@preconcurrency import Translation

struct LanguagePickerView: View {
    @ObservedObject var settings: UserSettings
    var onLanguageSettingsChanged: (() -> Void)?
    var onOnlineFallbackChanged: (() -> Void)?

    @State private var translationAvailability: [String: TranslationAvailabilityState] = [:]

    private var sourceLanguage: SupportedLanguage {
        SupportedLanguage(rawValue: settings.sourceLanguage) ?? .english
    }

    private var targetLanguage: SupportedLanguage {
        SupportedLanguage(rawValue: settings.targetLanguage) ?? .korean
    }

    var body: some View {
        Form {
            Section("Source Language") {
                Picker("Recognize", selection: sourceLanguageBinding) {
                    Text("🌐 Auto").tag("auto")
                    ForEach(SupportedLanguage.allCases) { language in
                        Text("\(language.flagEmoji) \(language.displayName)")
                            .tag(language.rawValue)
                    }
                }
                .accessibilityLabel("Source language picker")
                .accessibilityHint("Select the language being spoken, or Auto to detect automatically")
                .pickerStyle(.menu)
            }

            Section("Target Language") {
                Picker("Translate to", selection: targetLanguageBinding) {
                    ForEach(SupportedLanguage.allCases) { language in
                        Text("\(language.flagEmoji) \(language.displayName)")
                            .tag(language.rawValue)
                    }
                }
                .accessibilityLabel("Target language picker")
                .accessibilityHint("Select the language to translate into")
                .pickerStyle(.menu)

                availabilityIndicator
            }

            Section("Translation") {
                Toggle("Use online fallback translation", isOn: onlineFallbackBinding)
                    .accessibilityLabel("Use online fallback translation")
                    .accessibilityHint("When enabled, text may be sent to Google Translate if Apple Translation is unavailable")

                Text("When disabled, OST only uses Apple Translation and shows a warning if the session is unavailable.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("When enabled, text may be sent to Google Translate.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button(action: swapLanguages) {
                    Label("Swap Languages", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Swap source and target languages")
                .accessibilityHint("Exchanges the source and target language selections")
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(settings.sourceLanguage == settings.targetLanguage || settings.sourceLanguage == "auto")
            }

            Section("Speech Recognition") {
                Toggle("On-device recognition", isOn: useOnDeviceBinding)
                    .accessibilityLabel("On-device recognition toggle")
                    .accessibilityHint("When enabled, OST uses on-device speech recognition when the selected language model is available")

                if settings.useOnDeviceRecognition {
                    Text("Uses the on-device speech model when available.\nSystem Settings > Keyboard > Dictation > Languages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Server-based recognition requires Siri & Dictation to be enabled and an internet connection.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .task(id: "\(settings.sourceLanguage)-\(settings.targetLanguage)") {
            await checkAvailability()
        }
    }

    // MARK: - Availability

    private var pairKey: String {
        "\(sourceLanguage.rawValue)->\(targetLanguage.rawValue)"
    }

    private var isSameLanguagePair: Bool {
        settings.sourceLanguage != "auto"
            && TranslationConfig.isSameLanguagePair(
                source: sourceLanguage.translationLocale,
                target: targetLanguage.translationLocale
            )
    }

    private var isAutoSource: Bool {
        settings.sourceLanguage == "auto"
    }

    @State private var showTranslationDownload: Bool = false

    private var availabilityIndicator: some View {
        let availability = translationAvailability[pairKey]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(availabilityColor(availability))
                    .frame(width: 8, height: 8)
                Text(availabilityText(availability))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(availabilityAccessibilityLabel(availability))

            if !isAutoSource && !isSameLanguagePair && availability == .supported {
                Button("Download Translation Pack...") {
                    showTranslationDownload = true
                }
                .font(.caption)
                .translationPresentation(isPresented: $showTranslationDownload,
                    text: "Hello")
            }
        }
    }

    private func availabilityColor(_ availability: TranslationAvailabilityState?) -> Color {
        if isAutoSource { return .gray }
        if isSameLanguagePair { return .green }
        switch availability {
        case .installed:
            return .green
        case .supported:
            return .orange
        case .unsupported:
            return .red
        case nil:
            return .gray
        }
    }

    private func availabilityText(_ availability: TranslationAvailabilityState?) -> String {
        if isAutoSource {
            return "Checked after language is detected"
        }
        if isSameLanguagePair {
            return "No translation needed"
        }
        switch availability {
        case .installed:
            return "Apple Translation installed"
        case .supported:
            return "Download required"
        case .unsupported:
            return "Apple Translation unsupported"
        case nil:
            return "Checking..."
        }
    }

    private func availabilityAccessibilityLabel(_ availability: TranslationAvailabilityState?) -> String {
        if isAutoSource {
            return "Translation availability will be checked after the source language is detected"
        }
        if isSameLanguagePair {
            return "No translation needed for \(sourceLanguage.displayName)"
        }
        switch availability {
        case .installed:
            return "Translation installed for \(sourceLanguage.displayName) to \(targetLanguage.displayName)"
        case .supported:
            return "Translation pack can be downloaded for \(sourceLanguage.displayName) to \(targetLanguage.displayName)"
        case .unsupported:
            return "Translation unsupported for \(sourceLanguage.displayName) to \(targetLanguage.displayName)"
        case nil:
            return "Checking translation availability for \(sourceLanguage.displayName) to \(targetLanguage.displayName)"
        }
    }

    private func checkAvailability() async {
        guard !isAutoSource else { return }
        let key = pairKey
        let source = sourceLanguage.translationLocale
        let target = targetLanguage.translationLocale
        let availability = await TranslationConfig.availabilityState(
            source: source,
            target: target
        )
        guard !Task.isCancelled else { return }
        translationAvailability[key] = availability
    }

    // MARK: - Actions

    private func swapLanguages() {
        guard settings.sourceLanguage != "auto" else { return }
        let oldSource = sourceLanguage.displayName
        let oldTarget = targetLanguage.displayName
        let previous = settings.sourceLanguage
        settings.sourceLanguage = settings.targetLanguage
        settings.targetLanguage = previous
        onLanguageSettingsChanged?()
        AccessibilityManager.announce("Languages swapped: \(oldTarget) to \(oldSource)")
    }

    private var sourceLanguageBinding: Binding<String> {
        Binding(
            get: { settings.sourceLanguage },
            set: { newValue in
                settings.sourceLanguage = newValue
                onLanguageSettingsChanged?()
            }
        )
    }

    private var targetLanguageBinding: Binding<String> {
        Binding(
            get: { settings.targetLanguage },
            set: { newValue in
                settings.targetLanguage = newValue
                onLanguageSettingsChanged?()
            }
        )
    }

    private var onlineFallbackBinding: Binding<Bool> {
        Binding(
            get: { settings.allowOnlineTranslationFallback },
            set: { newValue in
                settings.allowOnlineTranslationFallback = newValue
                onOnlineFallbackChanged?()
            }
        )
    }

    private var useOnDeviceBinding: Binding<Bool> {
        Binding(
            get: { settings.useOnDeviceRecognition },
            set: { newValue in
                settings.useOnDeviceRecognition = newValue
                onLanguageSettingsChanged?()
            }
        )
    }
}
