import Foundation
import Translation

@MainActor
final class TranslationService: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    private var session: TranslationSession?

    func configure(source: Locale.Language, target: Locale.Language) {
        session = nil
        configuration = TranslationSession.Configuration(
            source: source,
            target: target
        )
    }

    /// Called by the SwiftUI view's .translationTask modifier when a session is ready.
    func handleSession(_ session: TranslationSession) {
        self.session = session
        AppLogger.shared.log("Translation session stored", category: .translation)
    }

    /// Clears the session reference to prevent stale usage after overlay is hidden.
    func invalidateSession() {
        session = nil
    }

    func translate(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let session {
            let response = try await session.translate(trimmed)
            return response.targetText
        }

        // Fallback: free Google Translate API
        AppLogger.shared.log("No session, using fallback translation", category: .translation)
        return try await fallbackTranslation(trimmed)
    }

    private func fallbackTranslation(_ text: String) async throws -> String {
        let sourceLang = configuration?.source?.languageCode?.identifier ?? "en"
        let targetLang = configuration?.target?.languageCode?.identifier ?? "ko"
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let urlString = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(sourceLang)&tl=\(targetLang)&dt=t&q=\(encoded)"

        guard let url = URL(string: urlString) else { return text }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            AppLogger.shared.log("Fallback translation HTTP \(httpResponse.statusCode)", category: .error)
            return text
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = json.first as? [Any] else {
            return text
        }

        var result = ""
        for sentence in sentences {
            if let parts = sentence as? [Any], let translated = parts.first as? String {
                result += translated
            }
        }

        return result.isEmpty ? text : result
    }
}
