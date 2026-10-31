import Foundation

public enum ProviderID: String, Codable, Sendable, CaseIterable, Hashable {
    case appleSpeech
    case appleTranslation
    case qwen3ASR
    case qwen3Translation
}

public struct TranscriptionCapabilities: Sendable, Equatable {
    public let supportedLanguages: Set<SupportedLanguage>
    public let supportsAutomaticLanguageDetection: Bool
    public let supportsVolatileResults: Bool

    public init(
        supportedLanguages: Set<SupportedLanguage>,
        supportsAutomaticLanguageDetection: Bool,
        supportsVolatileResults: Bool
    ) {
        self.supportedLanguages = supportedLanguages
        self.supportsAutomaticLanguageDetection = supportsAutomaticLanguageDetection
        self.supportsVolatileResults = supportsVolatileResults
    }
}

public struct TranslationCapabilities: Sendable, Equatable {
    public let supportedLanguages: Set<SupportedLanguage>
    public let isExperimental: Bool

    public init(supportedLanguages: Set<SupportedLanguage>, isExperimental: Bool) {
        self.supportedLanguages = supportedLanguages
        self.isExperimental = isExperimental
    }
}

public struct TranscriptionConfiguration: Sendable, Equatable {
    public let sourceMode: SourceLanguageMode
    public let chineseScriptPreference: ChineseScriptPreference
    public let modelDirectory: URL?
    public let endpointSilenceSeconds: Double
    public let vocabulary: [String]

    public init(
        sourceMode: SourceLanguageMode,
        chineseScriptPreference: ChineseScriptPreference,
        modelDirectory: URL? = nil,
        endpointSilenceSeconds: Double = 0.8,
        vocabulary: [String] = []
    ) {
        self.sourceMode = sourceMode
        self.chineseScriptPreference = chineseScriptPreference
        self.modelDirectory = modelDirectory
        self.endpointSilenceSeconds = min(max(endpointSilenceSeconds, 0.4), 2)
        self.vocabulary = TranscriptionVocabulary.terms(from: vocabulary.joined(separator: "\n"))
    }
}

public struct TranslationRequest: Sendable, Equatable {
    public let segmentID: UUID
    public let sourceLanguage: SupportedLanguage
    public let targetLanguage: SupportedLanguage
    public let sourceText: String
    public let isFinal: Bool

    public init(
        segmentID: UUID,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage,
        sourceText: String,
        isFinal: Bool
    ) {
        self.segmentID = segmentID
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.sourceText = sourceText
        self.isFinal = isFinal
    }
}

public struct TranslationResult: Sendable, Equatable {
    public let segmentID: UUID
    public let translatedText: String
    public let provider: ProviderID

    public init(segmentID: UUID, translatedText: String, provider: ProviderID) {
        self.segmentID = segmentID
        self.translatedText = translatedText
        self.provider = provider
    }
}

public protocol TranscriptionProvider: Actor {
    var id: ProviderID { get }
    var capabilities: TranscriptionCapabilities { get }
    func prepare(configuration: TranscriptionConfiguration) async throws
    func transcribe(_ audio: AsyncStream<PCMChunk>) -> AsyncThrowingStream<TranscriptEvent, Error>
    func stop() async
}

public protocol TranslationProvider: Actor {
    var id: ProviderID { get }
    var capabilities: TranslationCapabilities { get }
    func prepare(source: SupportedLanguage, target: SupportedLanguage) async throws
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
    func cancelAll() async
}
