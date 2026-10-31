import Foundation

public enum AudioSource: String, Sendable, CaseIterable {
    case systemAudio
    case microphone
}

public struct PCMChunk: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double
    public let startTime: Duration

    public init(samples: [Float], sampleRate: Double = 16_000, startTime: Duration = .zero) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.startTime = startTime
    }
}

public struct TranscriptSegment: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let startTime: Duration
    public var endTime: Duration?
    public var language: SupportedLanguage
    public var sourceText: String
    public var translatedText: String?
    public var isFinal: Bool
    public var audioSource: AudioSource

    public init(
        id: UUID = UUID(),
        startTime: Duration,
        endTime: Duration? = nil,
        language: SupportedLanguage,
        sourceText: String,
        translatedText: String? = nil,
        isFinal: Bool,
        audioSource: AudioSource = .systemAudio
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.language = language
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.isFinal = isFinal
        self.audioSource = audioSource
    }
}

public enum TranscriptEvent: Sendable, Equatable {
    case segment(TranscriptSegment)
    case unsupportedLanguage
    case silence
    case overload

    public var segment: TranscriptSegment? {
        guard case .segment(let segment) = self else { return nil }
        return segment
    }
}
