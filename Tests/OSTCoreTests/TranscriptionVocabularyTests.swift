import Foundation
import OSTCore
import Testing

@Test func vocabularyPreservesSpellingAndPhrasesWhileRemovingDuplicates() {
    let text = "  PyTorch  \r\npytorch\n\n파이토치\rOpen\t AI\nOpen AI\nC++\n東京\n中文"
    #expect(TranscriptionVocabulary.terms(from: text) == [
        "PyTorch", "파이토치", "Open AI", "C++", "東京", "中文",
    ])
    #expect(TranscriptionVocabulary.terms(from: " \n\t\r\n").isEmpty)
}

@Test func vocabularyBoundsTheContextPassedToProviders() {
    let terms = (1...120).map { "Term \($0)" }
    let configuration = TranscriptionConfiguration(
        sourceMode: .fixed(.english),
        chineseScriptPreference: .simplified,
        vocabulary: [" ", "Term 1"] + terms
    )
    #expect(configuration.vocabulary == Array(terms.prefix(100)))
    let longTerm = String(repeating: "가", count: 5_000)
    #expect(TranscriptionVocabulary.terms(from: longTerm).first?.count == 4_000)
}

@Test func vocabularyPreferencesPreserveRawInputAndOldPreferences() throws {
    let old = try JSONDecoder().decode(PreferencesSnapshot.self, from: Data("{}".utf8))
    #expect(old.transcriptionVocabulary.isEmpty)
    let original = PreferencesSnapshot(transcriptionVocabulary: "PyTorch\n파이토치\n")
    let restored = try JSONDecoder().decode(
        PreferencesSnapshot.self,
        from: JSONEncoder().encode(original)
    )
    #expect(restored == original)
    #expect(PreferencesSnapshot(
        transcriptionVocabulary: String(repeating: "a", count: 5_000)
    ).transcriptionVocabulary.count == 4_000)
}

@Test func vocabularyAddsHintsWithoutChangingTheEmptyPrompt() {
    #expect(MLXPromptDefaults.renderTranscription(vocabulary: []) == MLXPromptDefaults.transcription)
    let configuration = TranscriptionConfiguration(
        sourceMode: .automatic,
        chineseScriptPreference: .simplified,
        vocabulary: ["PyTorch", "파이토치", "Open AI"]
    )
    let prompt = MLXPromptDefaults.renderTranscription(vocabulary: configuration.vocabulary)
    #expect(prompt.hasPrefix(MLXPromptDefaults.transcription))
    #expect(prompt.contains("Vocabulary: PyTorch, 파이토치, Open AI"))
    #expect(prompt.contains("Do not insert unspoken terms."))
}

@Test func vocabularyPromptEchoIsRemovedWithoutRemovingSpokenTerms() {
    let prompt = MLXPromptDefaults.renderTranscription(vocabulary: ["PyTorch", "파이토치"])
    let output = "\(prompt)\nTranscript: PyTorch"
    #expect(MLXModelOutputSanitizer.transcription(
        output,
        prompt: prompt,
        language: .english
    ) == "PyTorch")
    #expect(MLXModelOutputSanitizer.transcription(
        "파이토치",
        prompt: prompt,
        language: .korean
    ) == "파이토치")
}
