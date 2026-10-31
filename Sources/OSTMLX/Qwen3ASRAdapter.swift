import Foundation
import MLX
import MLXAudioSTT
import OSTCore

public enum Qwen3ASRAdapterError: Error, Sendable {
    case modelDirectoryMissing
    case modelNotPrepared
    case unsupportedLanguage(String?)
}

private struct UtteranceSegmenter {
    enum Event {
        case idle
        case started([Float])
        case continued([Float])
        case ended([Float])
    }

    private let speechThreshold: Float = 0.005
    private let requiredSilenceSamples: Int
    private let maximumSamples: Int
    private let preRollLimit: Int

    private var preRoll: [Float] = []
    private var utterance: [Float] = []
    private var silenceSamples = 0
    private var active = false

    init(
        sampleRate: Int = 16_000,
        endpointSilenceSeconds: Double = 0.8,
        maximumUtteranceSeconds: Double = 15
    ) {
        requiredSilenceSamples = max(1, Int((Double(sampleRate) * endpointSilenceSeconds).rounded()))
        maximumSamples = max(1, Int((Double(sampleRate) * maximumUtteranceSeconds).rounded()))
        preRollLimit = sampleRate / 4
    }

    mutating func consume(_ samples: [Float]) -> Event {
        guard !samples.isEmpty else { return .idle }
        let rms = sqrt(samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count))
        let isSpeech = rms >= speechThreshold

        if !active {
            if isSpeech {
                active = true
                utterance = preRoll + samples
                preRoll.removeAll(keepingCapacity: true)
                silenceSamples = 0
                return .started(samples)
            }
            preRoll.append(contentsOf: samples)
            if preRoll.count > preRollLimit {
                preRoll.removeFirst(preRoll.count - preRollLimit)
            }
            return .idle
        }

        utterance.append(contentsOf: samples)
        silenceSamples = isSpeech ? 0 : silenceSamples + samples.count
        if silenceSamples >= requiredSilenceSamples || utterance.count >= maximumSamples {
            let complete = utterance
            reset()
            return .ended(complete)
        }
        return .continued(samples)
    }

    mutating func flush() -> [Float]? {
        guard active, !utterance.isEmpty else { return nil }
        let complete = utterance
        reset()
        return complete
    }

    private mutating func reset() {
        active = false
        utterance.removeAll(keepingCapacity: false)
        silenceSamples = 0
        preRoll.removeAll(keepingCapacity: true)
    }
}

public actor Qwen3ASRAdapter: TranscriptionProvider {
    public nonisolated let id: ProviderID = .qwen3ASR
    public nonisolated let capabilities = TranscriptionCapabilities(
        supportedLanguages: Set(SupportedLanguage.allCases),
        supportsAutomaticLanguageDetection: true,
        supportsVolatileResults: true
    )

    private var model: Qwen3ASRModel?
    private var configuration: TranscriptionConfiguration?
    private var runTask: Task<Void, Never>?
    private var streamingSession: StreamingInferenceSession?
    private var streamingEventsTask: Task<Void, Never>?
    private let languageStabilizer = AutomaticLanguageStabilizer()

    public init() {}

    public func prepare(configuration: TranscriptionConfiguration) async throws {
        guard let directory = configuration.modelDirectory else {
            throw Qwen3ASRAdapterError.modelDirectoryMissing
        }
        model = try await Qwen3ASRModel.fromModelDirectory(directory)
        self.configuration = configuration
        await languageStabilizer.reset()
    }

    public func transcribe(_ audio: AsyncStream<PCMChunk>) -> AsyncThrowingStream<TranscriptEvent, Error> {
        guard model != nil, configuration != nil else {
            return AsyncThrowingStream { $0.finish(throwing: Qwen3ASRAdapterError.modelNotPrepared) }
        }

        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return }
                await self.run(audio: audio, continuation: continuation)
            }
            Task { self.setRunTask(task) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stop() {
        runTask?.cancel()
        runTask = nil
        streamingEventsTask?.cancel()
        streamingEventsTask = nil
        streamingSession?.cancel()
        streamingSession = nil
        model = nil
        configuration = nil
        Memory.clearCache()
    }

    private func run(
        audio: AsyncStream<PCMChunk>,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    ) async {
        guard let model, let configuration else {
            continuation.finish(throwing: Qwen3ASRAdapterError.modelNotPrepared)
            return
        }

        var segmenter = UtteranceSegmenter(
            endpointSilenceSeconds: configuration.endpointSilenceSeconds
        )
        var silenceDetector = SilenceDetector()
        var activeSegmentID: UUID?
        do {
            for await chunk in audio {
                try Task.checkCancellation()
                if silenceDetector.observe(chunk.samples) {
                    continuation.yield(.silence)
                }
                switch segmenter.consume(chunk.samples) {
                case .idle:
                    continue
                case .started(let samples):
                    let segmentID = UUID()
                    activeSegmentID = segmentID
                    startStreaming(
                        model: model,
                        segmentID: segmentID,
                        configuration: configuration,
                        continuation: continuation
                    )
                    streamingSession?.feedAudio(samples: samples)
                case .continued(let samples):
                    streamingSession?.feedAudio(samples: samples)
                case .ended(let utterance):
                    streamingSession?.stop()
                    streamingEventsTask?.cancel()
                    streamingEventsTask = nil
                    streamingSession = nil
                    let segmentID = activeSegmentID ?? UUID()
                    activeSegmentID = nil
                    try await emitFinal(
                        model: model,
                        samples: utterance,
                        segmentID: segmentID,
                        configuration: configuration,
                        continuation: continuation
                    )
                }
            }
            if let remaining = segmenter.flush() {
                try await emitFinal(
                    model: model,
                    samples: remaining,
                    segmentID: activeSegmentID ?? UUID(),
                    configuration: configuration,
                    continuation: continuation
                )
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func startStreaming(
        model: Qwen3ASRModel,
        segmentID: UUID,
        configuration: TranscriptionConfiguration,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    ) {
        guard case .fixed(let language) = configuration.sourceMode else { return }
        let session = StreamingInferenceSession(
            model: model,
            config: StreamingConfig(
                decodeIntervalSeconds: 0.8,
                delayPreset: .agent,
                language: language.modelLanguageName,
                temperature: 0,
                maxTokensPerPass: 256,
                maxDecodeWindows: 2
            )
        )
        streamingSession = session
        streamingEventsTask = Task {
            for await event in session.events {
                guard !Task.isCancelled else { return }
                switch event {
                case .provisional(let text):
                    let sanitized = MLXModelOutputSanitizer.transcription(
                        text,
                        prompt: MLXPromptDefaults.transcription,
                        language: language
                    )
                    guard !sanitized.isEmpty else { continue }
                    continuation.yield(.segment(TranscriptSegment(
                        id: segmentID,
                        startTime: .zero,
                        language: language,
                        sourceText: sanitized,
                        isFinal: false
                    )))
                case .displayUpdate(let confirmed, let provisional):
                    let sanitized = MLXModelOutputSanitizer.transcription(
                        confirmed + provisional,
                        prompt: MLXPromptDefaults.transcription,
                        language: language
                    )
                    guard !sanitized.isEmpty else { continue }
                    continuation.yield(.segment(TranscriptSegment(
                        id: segmentID,
                        startTime: .zero,
                        language: language,
                        sourceText: sanitized,
                        isFinal: false
                    )))
                case .confirmed, .stats, .ended:
                    break
                }
            }
        }
    }

    private func emitFinal(
        model: Qwen3ASRModel,
        samples: [Float],
        segmentID: UUID,
        configuration: TranscriptionConfiguration,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    ) async throws {
        try Task.checkCancellation()
        let requestedLanguage: String?
        switch configuration.sourceMode {
        case .fixed(let language): requestedLanguage = language.modelLanguageName
        case .automatic: requestedLanguage = nil
        }
        let prompt = MLXPromptDefaults.renderTranscription(vocabulary: configuration.vocabulary)
        let output = model.generate(
            audio: MLXArray(samples),
            maxTokens: 512,
            temperature: 0,
            context: prompt,
            language: requestedLanguage,
            chunkDuration: 15,
            minChunkDuration: 1
        )
        try Task.checkCancellation()

        let language: SupportedLanguage
        switch configuration.sourceMode {
        case .fixed(let fixed):
            language = fixed
        case .automatic:
            guard let detected = try? Self.mapDetectedLanguage(
                    output.language,
                    chinesePreference: configuration.chineseScriptPreference
                  ) else {
                continuation.yield(.unsupportedLanguage)
                return
            }
            language = await languageStabilizer.observe(detected)
        }
        let text = MLXModelOutputSanitizer.transcription(
            output.text,
            prompt: prompt,
            language: language
        )
        guard !text.isEmpty else {
            continuation.yield(.silence)
            return
        }
        let duration = Double(samples.count) / 16_000
        continuation.yield(.segment(TranscriptSegment(
            id: segmentID,
            startTime: .zero,
            endTime: .seconds(duration),
            language: language,
            sourceText: text,
            isFinal: true
        )))
        if output.totalTime > duration, duration > 0 {
            continuation.yield(.overload)
        }
    }

    private static func mapDetectedLanguage(
        _ value: String?,
        chinesePreference: ChineseScriptPreference
    ) throws -> SupportedLanguage {
        switch value?.lowercased() {
        case "en", "english": .english
        case "zh", "chinese", "mandarin": chinesePreference.language
        case "ja", "japanese": .japanese
        case "ko", "korean": .korean
        default: throw Qwen3ASRAdapterError.unsupportedLanguage(value)
        }
    }

    private func setRunTask(_ task: Task<Void, Never>) {
        runTask = task
    }
}
