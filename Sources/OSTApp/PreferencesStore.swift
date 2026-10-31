import Foundation
import Combine
import OSTCore

@MainActor
final class PreferencesStore: ObservableObject {
    private static let storageKey = "OST.preferences.v1"

    @Published var snapshot: PreferencesSnapshot {
        didSet {
            persist()
            onChange?(snapshot)
        }
    }

    var onChange: ((PreferencesSnapshot) -> Void)?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let initialSnapshot: PreferencesSnapshot
        if let data = userDefaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(PreferencesSnapshot.self, from: data) {
            initialSnapshot = decoded
        } else {
            initialSnapshot = PreferencesSnapshot(
                sourceMode: .fixed(Self.defaultSourceLanguage()),
                targetLanguage: Self.defaultTargetLanguage()
            )
        }
        snapshot = Self.normalizedTranscriptionSettings(initialSnapshot)
        if snapshot != initialSnapshot,
           let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: Self.storageKey)
        }
    }

    private let userDefaults: UserDefaults

    var sourceMode: SourceLanguageMode {
        get { snapshot.sourceMode }
        set { snapshot.sourceMode = newValue }
    }

    var targetLanguage: SupportedLanguage {
        get { snapshot.targetLanguage }
        set { snapshot.targetLanguage = newValue }
    }

    var chineseScriptPreference: ChineseScriptPreference {
        get { snapshot.chineseScriptPreference }
        set { snapshot.chineseScriptPreference = newValue }
    }

    var transcriptionProvider: ProviderID {
        get { snapshot.transcriptionProvider }
        set { snapshot.transcriptionProvider = newValue }
    }

    func selectTranscriptionProvider(_ provider: ProviderID) {
        var updated = snapshot
        updated.transcriptionProvider = provider
        updated = Self.normalizedTranscriptionSettings(updated)
        snapshot = updated
    }

    var translationProvider: ProviderID {
        get { snapshot.translationProvider }
        set { snapshot.translationProvider = newValue }
    }

    var selectedASRModelID: String {
        get { snapshot.selectedASRModelID }
        set { snapshot.selectedASRModelID = newValue }
    }

    var selectedTranslationModelID: String {
        get { snapshot.selectedTranslationModelID }
        set { snapshot.selectedTranslationModelID = newValue }
    }

    var mlxTranslationPrompt: String {
        get { snapshot.mlxTranslationPrompt }
        set { snapshot.mlxTranslationPrompt = String(newValue.prefix(4_000)) }
    }

    var transcriptionVocabulary: String {
        get { snapshot.transcriptionVocabulary }
        set {
            snapshot.transcriptionVocabulary = String(newValue.prefix(TranscriptionVocabulary.maximumCharacters))
        }
    }

    var overlayLayout: OverlayLayout {
        get { snapshot.overlayLayout }
        set { snapshot.overlayLayout = newValue }
    }

    var microphoneMode: MicrophoneMode {
        get { snapshot.microphoneMode }
        set { snapshot.microphoneMode = newValue }
    }

    var microphoneColor: RGBAColor {
        get { snapshot.microphoneColor }
        set { snapshot.microphoneColor = newValue }
    }

    var subtitleDisplayMode: SubtitleDisplayMode {
        get { snapshot.subtitleDisplayMode }
        set { snapshot.subtitleDisplayMode = newValue }
    }

    var overlayLocked: Bool {
        get { snapshot.overlayLocked }
        set { snapshot.overlayLocked = newValue }
    }

    var sourceFontSize: Double {
        get { snapshot.sourceFontSize }
        set { snapshot.sourceFontSize = min(max(newValue, 12), 72) }
    }

    var translationFontSize: Double {
        get { snapshot.translationFontSize }
        set { snapshot.translationFontSize = min(max(newValue, 12), 72) }
    }

    var previewFontSize: Double {
        get { snapshot.previewFontSize }
        set { snapshot.previewFontSize = min(max(newValue, 12), 72) }
    }

    var sourceColor: RGBAColor {
        get { snapshot.sourceColor }
        set { snapshot.sourceColor = newValue }
    }

    var translationColor: RGBAColor {
        get { snapshot.translationColor }
        set { snapshot.translationColor = newValue }
    }

    var previewColor: RGBAColor {
        get { snapshot.previewColor }
        set { snapshot.previewColor = newValue }
    }

    var backgroundColor: RGBAColor {
        get { snapshot.backgroundColor }
        set { snapshot.backgroundColor = newValue }
    }

    var backgroundOpacity: Double {
        get { snapshot.backgroundOpacity }
        set { snapshot.backgroundOpacity = min(max(newValue, 0), 1) }
    }

    var overlayLineCount: Int {
        get { snapshot.overlayLineCount }
        set { snapshot.overlayLineCount = min(max(newValue, 2), 10) }
    }

    var endpointSilenceSeconds: Double {
        get { snapshot.endpointSilenceSeconds }
        set { snapshot.endpointSilenceSeconds = min(max(newValue, 0.4), 2) }
    }

    var subtitleAlignment: SubtitleAlignment {
        get { snapshot.subtitleAlignment }
        set { snapshot.subtitleAlignment = newValue }
    }

    var appDisplayLanguage: AppDisplayLanguage {
        get { snapshot.appDisplayLanguage }
        set { snapshot.appDisplayLanguage = newValue }
    }

    var sessionLoggingEnabled: Bool {
        get { snapshot.sessionLoggingEnabled }
        set { snapshot.sessionLoggingEnabled = newValue }
    }

    var sessionLogDirectoryBookmark: Data? {
        get { snapshot.sessionLogDirectoryBookmark }
        set { snapshot.sessionLogDirectoryBookmark = newValue }
    }

    var sessionLogDirectoryPath: String? {
        get { snapshot.sessionLogDirectoryPath }
        set { snapshot.sessionLogDirectoryPath = newValue }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func defaultSourceLanguage() -> SupportedLanguage {
        switch Locale.current.language.languageCode?.identifier {
        case "zh":
            return Locale.current.language.script?.identifier == "Hant"
                ? .chineseTraditional : .chineseSimplified
        case "ja": return .japanese
        case "ko": return .korean
        default: return .english
        }
    }

    private static func defaultTargetLanguage() -> SupportedLanguage {
        let source = defaultSourceLanguage()
        return source == .english ? .korean : .english
    }

    private static func normalizedTranscriptionSettings(
        _ snapshot: PreferencesSnapshot
    ) -> PreferencesSnapshot {
        guard snapshot.transcriptionProvider == .appleSpeech,
              case .automatic = snapshot.sourceMode else {
            return snapshot
        }
        var normalized = snapshot
        normalized.sourceMode = .fixed(defaultSourceLanguage())
        return normalized
    }
}
