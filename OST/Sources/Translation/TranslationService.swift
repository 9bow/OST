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

    /// Translates text with context from recent entries for consistency.
    /// Sends context + new text separated by newlines, then extracts only the new translation.
    func translateWithContext(_ text: String, context: [String]) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard !context.isEmpty, let session else {
            return try await translate(trimmed)
        }

        let fullText = context.joined(separator: "\n") + "\n" + trimmed
        let response = try await session.translate(fullText)
        let resultLines = response.targetText.components(separatedBy: "\n")
        let contextLineCount = context.count
        if resultLines.count > contextLineCount {
            return resultLines.dropFirst(contextLineCount).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return response.targetText
    }

    private func fallbackTranslation(_ text: String) async throws -> String {
        let sourceLang = configuration?.source?.languageCode?.identifier ?? "en"
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let urlString = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(sourceLang)&tl=ko&dt=t&q=\(encoded)"

        guard let url = URL(string: urlString) else { return text }

        let (data, _) = try await URLSession.shared.data(from: url)

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
