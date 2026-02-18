import Translation

struct TranslationConfig {
    let sourceLanguage: Locale.Language
    let targetLanguage: Locale.Language
    let isAvailable: Bool

    static func checkAvailability(
        source: Locale.Language,
        target: Locale.Language
    ) async -> Bool {
        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: target)
        switch status {
        case .installed, .supported:
            return true
        case .unsupported:
            return false
        @unknown default:
            return false
        }
    }
}
