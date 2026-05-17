@preconcurrency import Translation

enum TranslationAvailabilityState {
    case installed
    case supported
    case unsupported
}

enum TranslationConfig {
    static func isSameLanguagePair(
        source: Locale.Language,
        target: Locale.Language
    ) -> Bool {
        guard source.languageCode?.identifier == target.languageCode?.identifier else {
            return false
        }

        let sourceScript = source.script?.identifier
        let targetScript = target.script?.identifier
        if sourceScript != nil || targetScript != nil {
            return sourceScript == targetScript
        }

        return true
    }

    static func availabilityState(
        source: Locale.Language,
        target: Locale.Language
    ) async -> TranslationAvailabilityState {
        if isSameLanguagePair(source: source, target: target) {
            return .installed
        }

        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: target)
        switch status {
        case .installed:
            return .installed
        case .supported:
            return .supported
        case .unsupported:
            return .unsupported
        @unknown default:
            return .unsupported
        }
    }
}
