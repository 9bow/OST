import SwiftUI
import Translation

struct LanguagePickerView: View {
    @ObservedObject var settings: UserSettings
    @State private var translationAvailability: [String: Bool] = [:]

    private var sourceLanguage: SupportedLanguage {
        SupportedLanguage(rawValue: settings.sourceLanguage) ?? .english
    }

    private var targetLanguage: SupportedLanguage {
        SupportedLanguage(rawValue: settings.targetLanguage) ?? .korean
    }

    var body: some View {
        Form {
            Section("Source Language") {
                Picker("Recognize", selection: $settings.sourceLanguage) {
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
                Picker("Translate to", selection: $settings.targetLanguage) {
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
                Toggle("On-device recognition", isOn: $settings.useOnDeviceRecognition)
                    .accessibilityLabel("On-device recognition toggle")
                    .accessibilityHint("When enabled, speech recognition runs locally on device")

                if settings.useOnDeviceRecognition {
                    Text("Requires on-device speech model download.\nSystem Settings > Keyboard > Dictation > Languages")
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

    @State private var showTranslationDownload: Bool = false

    private var availabilityIndicator: some View {
        let isAvailable = translationAvailability[pairKey]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isAvailable == true ? .green : (isAvailable == false ? .orange : .gray))
                    .frame(width: 8, height: 8)
                Text(isAvailable == true ? "Translation pack installed" : (isAvailable == false ? "Download required" : "Checking..."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Translation \(isAvailable == true ? "available" : "not available") for \(sourceLanguage.displayName) to \(targetLanguage.displayName)")

            if isAvailable == false {
                Button("Download Translation Pack...") {
                    showTranslationDownload = true
                }
                .font(.caption)
                .translationPresentation(isPresented: $showTranslationDownload,
                    text: "Hello")
            }
        }
    }

    private func checkAvailability() async {
        let available = await TranslationConfig.checkAvailability(
            source: sourceLanguage.translationLocale,
            target: targetLanguage.translationLocale
        )
        translationAvailability[pairKey] = available
    }

    // MARK: - Actions

    private func swapLanguages() {
        guard settings.sourceLanguage != "auto" else { return }
        let oldSource = sourceLanguage.displayName
        let oldTarget = targetLanguage.displayName
        let previous = settings.sourceLanguage
        settings.sourceLanguage = settings.targetLanguage
        settings.targetLanguage = previous
        AccessibilityManager.announce("Languages swapped: \(oldTarget) to \(oldSource)")
    }
}
