import Foundation
@preconcurrency import Translation

enum TranslationServiceError: LocalizedError {
    case sessionUnavailable
    case configurationUnavailable
    case staleConfiguration
    case invalidFallbackResponse
    case fallbackHTTPStatus(Int)

    var errorDescription: String? {
        switch self {
        case .sessionUnavailable:
            return "Translation is not ready. Open Settings > Languages to download the language pack, or enable online fallback translation."
        case .configurationUnavailable:
            return "Translation configuration is no longer available."
        case .staleConfiguration:
            return "Translation configuration changed before the request completed."
        case .invalidFallbackResponse:
            return "Online fallback translation returned an invalid response."
        case .fallbackHTTPStatus(let statusCode):
            return "Online fallback translation failed with HTTP \(statusCode)."
        }
    }
}

@MainActor
final class TranslationService: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastErrorMessage: String?

    private var session: TranslationSession?
    private(set) var allowsOnlineFallback: Bool = false
    private(set) var sourceLanguage: Locale.Language?
    private(set) var targetLanguage: Locale.Language?
    private(set) var configurationGeneration: Int = 0
    private var fallbackPolicyGeneration: Int = 0
    private var bypassesTranslationForSameLanguage: Bool = false

    func setOnlineFallbackEnabled(_ enabled: Bool, reportPendingStatus: Bool = true) {
        if allowsOnlineFallback != enabled {
            fallbackPolicyGeneration += 1
        }
        allowsOnlineFallback = enabled
        lastErrorMessage = nil
        guard reportPendingStatus else {
            statusMessage = nil
            return
        }
        if enabled {
            if session == nil && configuration != nil {
                statusMessage = "Online fallback enabled until Apple Translation is ready."
            }
        } else if session == nil && configuration != nil {
            statusMessage = "Translation is not ready. Open Settings > Languages if translation stays blank."
        }
    }

    func configure(source: Locale.Language, target: Locale.Language) {
        session = nil
        lastErrorMessage = nil
        configurationGeneration += 1
        sourceLanguage = source
        targetLanguage = target
        bypassesTranslationForSameLanguage = TranslationConfig.isSameLanguagePair(
            source: source,
            target: target
        )
        if bypassesTranslationForSameLanguage {
            statusMessage = nil
            configuration = nil
            return
        }

        statusMessage = "Preparing translation..."
        configuration = TranslationSession.Configuration(
            source: source,
            target: target
        )
    }

    /// Called by the SwiftUI view's .translationTask modifier when a session is ready.
    func handleSession(_ session: TranslationSession, generation: Int) {
        guard generation == configurationGeneration,
              configuration != nil,
              !bypassesTranslationForSameLanguage else {
            AppLogger.shared.log("Ignoring stale translation session", category: .translation)
            return
        }
        self.session = session
        statusMessage = nil
        lastErrorMessage = nil
        AppLogger.shared.log("Translation session stored", category: .translation)
    }

    /// Invalidates translation state. When preserving pending translations, keep
    /// the current configuration so queued final subtitles can finish.
    func invalidateSession(preservingPendingTranslations: Bool = false) {
        if preservingPendingTranslations {
            statusMessage = nil
            lastErrorMessage = nil
            return
        }

        session = nil
        configuration = nil
        configurationGeneration += 1
        sourceLanguage = nil
        targetLanguage = nil
        bypassesTranslationForSameLanguage = false
        statusMessage = nil
        lastErrorMessage = nil
    }

    func waitForSessionReady(timeout seconds: TimeInterval) async -> Bool {
        let expectedGeneration = configurationGeneration
        if bypassesTranslationForSameLanguage {
            return true
        }

        let deadline = Date().addingTimeInterval(seconds)
        while expectedGeneration == configurationGeneration,
              session == nil,
              configuration != nil,
              Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard expectedGeneration == configurationGeneration,
              configuration != nil else {
            return false
        }

        if session == nil {
            statusMessage = allowsOnlineFallback
                ? "Online fallback enabled until Apple Translation is ready."
                : "Translation is still preparing. Open Settings > Languages if translation stays blank."
        }
        return session != nil
    }

    func translate(_ text: String, generation: Int? = nil) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        try validateGeneration(generation)

        if bypassesTranslationForSameLanguage {
            statusMessage = nil
            lastErrorMessage = nil
            return trimmed
        }

        if let session {
            do {
                let response = try await session.translate(trimmed)
                try validateGeneration(generation)
                lastErrorMessage = nil
                return response.targetText
            } catch TranslationServiceError.staleConfiguration {
                throw TranslationServiceError.staleConfiguration
            } catch {
                if isCancellation(error) {
                    throw CancellationError()
                }
                try validateGeneration(generation)
                lastErrorMessage = "Translation failed: \(error.localizedDescription)"
                throw error
            }
        }

        guard allowsOnlineFallback else {
            let error = TranslationServiceError.sessionUnavailable
            lastErrorMessage = error.localizedDescription
            throw error
        }

        AppLogger.shared.log("No session, using online fallback translation", category: .translation)
        statusMessage = "Using online fallback translation"
        let expectedFallbackGeneration = fallbackPolicyGeneration
        do {
            let result = try await fallbackTranslation(trimmed)
            try validateGeneration(generation)
            try validateFallbackPolicyGeneration(expectedFallbackGeneration)
            lastErrorMessage = nil
            return result
        } catch TranslationServiceError.staleConfiguration {
            throw TranslationServiceError.staleConfiguration
        } catch {
            if isCancellation(error) {
                statusMessage = nil
                throw CancellationError()
            }
            try validateGeneration(generation)
            try validateFallbackPolicyGeneration(expectedFallbackGeneration)
            statusMessage = nil
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }

    private func fallbackTranslation(_ text: String) async throws -> String {
        guard let sourceLang = fallbackLanguageCode(for: sourceLanguage),
              let targetLang = fallbackLanguageCode(for: targetLanguage) else {
            throw TranslationServiceError.configurationUnavailable
        }

        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: sourceLang),
            URLQueryItem(name: "tl", value: targetLang),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]

        guard let url = components?.url else {
            throw TranslationServiceError.invalidFallbackResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            AppLogger.shared.log("Fallback translation HTTP \(httpResponse.statusCode)", category: .error)
            throw TranslationServiceError.fallbackHTTPStatus(httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = json.first as? [Any] else {
            throw TranslationServiceError.invalidFallbackResponse
        }

        var result = ""
        for sentence in sentences {
            if let parts = sentence as? [Any], let translated = parts.first as? String {
                result += translated
            }
        }

        guard !result.isEmpty else {
            throw TranslationServiceError.invalidFallbackResponse
        }
        return result
    }

    private func fallbackLanguageCode(for language: Locale.Language?) -> String? {
        guard let language,
              let languageCode = language.languageCode?.identifier else {
            return nil
        }

        if languageCode == "zh" {
            switch language.script?.identifier {
            case "Hans":
                return "zh-CN"
            case "Hant":
                return "zh-TW"
            default:
                break
            }
        }

        return languageCode
    }

    private func validateGeneration(_ generation: Int?) throws {
        if let generation, generation != configurationGeneration {
            throw TranslationServiceError.staleConfiguration
        }
    }

    private func validateFallbackPolicyGeneration(_ generation: Int) throws {
        if generation != fallbackPolicyGeneration || !allowsOnlineFallback {
            throw TranslationServiceError.staleConfiguration
        }
    }
}
