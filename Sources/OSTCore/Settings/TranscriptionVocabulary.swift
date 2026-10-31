import Foundation

public enum TranscriptionVocabulary {
    public static let maximumCharacters = 4_000
    public static let maximumTerms = 100

    public static func terms(from text: String) -> [String] {
        var seen: Set<String> = []
        return text.prefix(maximumCharacters)
            .split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(maximumTerms)
            .map { $0 }
    }
}
