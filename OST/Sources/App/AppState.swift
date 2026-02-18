import Foundation
import SwiftUI
import CoreMedia
import Combine
import NaturalLanguage

/// A single subtitle entry with timestamp for expiry.
struct SubtitleEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    var recognized: String
    var translated: String = ""
    var isFinal: Bool = false
}

/// Central observable state that owns the audio capture, speech recognition, and translation pipeline.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Published State

    @Published var isCapturing: Bool = false
    @Published private(set) var subtitleEntries: [SubtitleEntry] = []
    @Published private(set) var liveText: String = ""
    @Published var errorMessage: String? = nil

    // MARK: - Pipeline Components

    private let audioCapture = SystemAudioCapture()
    private let speechRecognizer: SpeechRecognizer
    let translationService = TranslationService()
    let sessionRecorder = SessionRecorder()

    // MARK: - Private State

    private var bufferConsumerTask: Task<Void, Never>?
    private var expiryTimer: Timer?
    private var speechPauseTimer: Timer?
    private var lastConsumedPartial: String = ""
    private var saveSessionHistory: Bool = true
    private var cancellables = Set<AnyCancellable>()
    private var autoDetectEnabled: Bool = false
    private var hasDetectedLanguage: Bool = false
    @Published var detectedLanguageDisplay: String = ""

    // Settings reference for expiry/max lines
    var maxSubtitleLines: Int = 3
    var subtitleExpirySeconds: Double = 10
    var speechPauseSeconds: Double = 2.0

    // MARK: - Init

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.speechRecognizer = SpeechRecognizer(locale: locale)
        setupTextBindings()
    }

    // MARK: - Public Interface

    /// Starts system audio capture and speech recognition.
    func startCapture(saveSession: Bool = true, useOnDevice: Bool = true) async {
        guard !isCapturing else { return }
        errorMessage = nil
        saveSessionHistory = saveSession

        AppLogger.shared.log("Starting capture...", category: .app)

        do {
            AppLogger.shared.log("Requesting speech recognition authorization", category: .speech)
            try await speechRecognizer.startRecognition(useOnDevice: useOnDevice)
            AppLogger.shared.log("Speech recognition started", category: .speech)

            AppLogger.shared.log("Starting audio capture", category: .audio)
            let buffers = try await audioCapture.startCapture()
            AppLogger.shared.log("Audio capture started", category: .audio)

            isCapturing = true
            lastConsumedPartial = ""
            subtitleEntries = []
            liveText = ""
            startConsumingBuffers(from: buffers)
            startExpiryTimer()

            if saveSession {
                sessionRecorder.startSession()
            }
        } catch {
            AppLogger.shared.log("Capture failed: \(error.localizedDescription)", category: .error)
            errorMessage = error.localizedDescription
            speechRecognizer.stopRecognition()
            return
        }
    }

    /// Stops capture and recognition, preserving last recognized text.
    func stopCapture() async {
        guard isCapturing else { return }

        bufferConsumerTask?.cancel()
        bufferConsumerTask = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
        speechPauseTimer?.invalidate()
        speechPauseTimer = nil

        await audioCapture.stopCapture()
        speechRecognizer.stopRecognition()

        isCapturing = false

        if saveSessionHistory {
            sessionRecorder.endSession()
        }
        AppLogger.shared.log("Capture stopped", category: .app)
    }

    /// Changes the speech recognition language.
    func changeSourceLanguage(to locale: Locale, useOnDevice: Bool = true) async {
        do {
            try await speechRecognizer.changeLanguage(locale: locale, useOnDevice: useOnDevice)
            lastConsumedPartial = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Enables automatic language detection from initial speech.
    func enableAutoDetect() {
        autoDetectEnabled = true
        hasDetectedLanguage = false
        detectedLanguageDisplay = ""
    }

    /// Detects language from partial text using NLLanguageRecognizer.
    private func detectLanguageIfNeeded(_ text: String) {
        guard autoDetectEnabled, !hasDetectedLanguage, text.count >= 15 else { return }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage,
              let confidence = recognizer.languageHypotheses(withMaximum: 1)[dominant],
              confidence > 0.5 else { return }

        let matched: SupportedLanguage?
        switch dominant {
        case .english: matched = .english
        case .simplifiedChinese, .traditionalChinese: matched = .chineseSimplified
        case .japanese: matched = .japanese
        case .korean: matched = .korean
        default: matched = nil
        }

        guard let target = matched else { return }
        hasDetectedLanguage = true
        detectedLanguageDisplay = target.displayName

        AppLogger.shared.log("Auto-detected language: \(target.displayName) (confidence: \(confidence))", category: .speech)

        Task {
            await changeSourceLanguage(to: target.speechLocale, useOnDevice: speechRecognizer.currentOnDeviceSetting)
            // Reset consumed state since recognizer restarts
            lastConsumedPartial = ""
            liveText = ""
        }
    }

    // MARK: - Private Helpers

    private func startConsumingBuffers(from buffers: AsyncStream<CMSampleBuffer>) {
        AppLogger.shared.log("Buffer consumer task started", category: .audio)
        var count = 0
        bufferConsumerTask = Task { [weak self] in
            guard let self else { return }
            for await buffer in buffers {
                if Task.isCancelled { break }
                count += 1
                if count <= 3 || count % 100 == 0 {
                    AppLogger.shared.log("Forwarding buffer #\(count) to speech recognizer", category: .speech)
                }
                self.speechRecognizer.append(buffer)
            }
            AppLogger.shared.log("Buffer consumer ended after \(count) buffers", category: .audio)
        }
    }

    private func setupTextBindings() {
        speechRecognizer.$currentText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentText in
                guard let self else { return }
                // Show only the unconsumed portion as live text
                if !self.lastConsumedPartial.isEmpty && currentText.hasPrefix(self.lastConsumedPartial) {
                    self.liveText = String(currentText.dropFirst(self.lastConsumedPartial.count)).trimmingCharacters(in: .whitespaces)
                } else if self.lastConsumedPartial.isEmpty {
                    self.liveText = currentText
                } else {
                    // currentText was reset (recognizer restarted) — start fresh
                    self.lastConsumedPartial = ""
                    self.liveText = currentText
                }
                self.detectLanguageIfNeeded(currentText)
                if currentText.isEmpty {
                    // Recognition ended/restarted — consume any remaining text
                    if !self.liveText.isEmpty {
                        self.consumeRemainingText()
                    }
                    self.lastConsumedPartial = ""
                    self.speechPauseTimer?.invalidate()
                    self.speechPauseTimer = nil
                } else {
                    self.resetSpeechPauseTimer()
                }
            }
            .store(in: &cancellables)
    }

    private func resetSpeechPauseTimer() {
        speechPauseTimer?.invalidate()
        speechPauseTimer = Timer.scheduledTimer(withTimeInterval: speechPauseSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handlePartialTextStabilized()
            }
        }
    }

    /// When partial recognition text hasn't changed for the configured pause duration, treat it as a completed segment.
    private func handlePartialTextStabilized() {
        let fullText = speechRecognizer.currentText
        guard !fullText.isEmpty, fullText != lastConsumedPartial, isCapturing else { return }

        // Extract only the NEW portion since last consumption
        let newText: String
        if !lastConsumedPartial.isEmpty && fullText.hasPrefix(lastConsumedPartial) {
            newText = String(fullText.dropFirst(lastConsumedPartial.count)).trimmingCharacters(in: .whitespaces)
        } else {
            newText = fullText
        }
        lastConsumedPartial = fullText

        guard !newText.isEmpty else { return }

        AppLogger.shared.log("Partial text stabilized: \"\(newText)\"", category: .speech)
        liveText = ""

        let chunks = splitIntoChunks(newText)
        for sentence in chunks {
            let entry = SubtitleEntry(timestamp: Date(), recognized: sentence, isFinal: true)
            subtitleEntries.append(entry)
            translateEntry(id: entry.id, text: sentence)
        }
        trimEntries()
    }

    /// Consumes any remaining live text into subtitle entries when the recognizer restarts.
    private func consumeRemainingText() {
        guard !liveText.isEmpty, isCapturing else { return }
        let text = liveText
        liveText = ""
        AppLogger.shared.log("Consuming remaining text before reset: \"\(text)\"", category: .speech)
        let chunks = splitIntoChunks(text)
        for sentence in chunks {
            let entry = SubtitleEntry(timestamp: Date(), recognized: sentence, isFinal: true)
            subtitleEntries.append(entry)
            translateEntry(id: entry.id, text: sentence)
        }
        trimEntries()
    }

    /// Translates a subtitle entry with context from recent entries for consistency.
    private func translateEntry(id: UUID, text: String) {
        let recentContext = subtitleEntries
            .filter { $0.id != id && !$0.recognized.isEmpty }
            .suffix(2)
            .map { $0.recognized }

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.translationService.translateWithContext(text, context: Array(recentContext))
                if let idx = self.subtitleEntries.firstIndex(where: { $0.id == id }) {
                    self.subtitleEntries[idx].translated = result
                    AppLogger.shared.log("Translated: \(text) → \(result)", category: .translation)
                    if self.saveSessionHistory {
                        self.sessionRecorder.record(recognized: text, translated: result)
                    }
                }
            } catch {
                AppLogger.shared.log("Translation failed: \(error.localizedDescription)", category: .error)
            }
        }
    }

    /// Splits text into manageable chunks: first by sentence, then by character limit.
    private func splitIntoChunks(_ text: String) -> [String] {
        let maxChars = 120

        // First split by sentences
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            if let s = substring?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
                sentences.append(s)
            }
        }
        if sentences.isEmpty { sentences = [text] }

        // Then split long sentences at word boundaries
        var chunks: [String] = []
        for sentence in sentences {
            if sentence.count <= maxChars {
                chunks.append(sentence)
            } else {
                var current = ""
                for word in sentence.split(separator: " ") {
                    let candidate = current.isEmpty ? String(word) : current + " " + word
                    if candidate.count > maxChars && !current.isEmpty {
                        chunks.append(current)
                        current = String(word)
                    } else {
                        current = candidate
                    }
                }
                if !current.isEmpty { chunks.append(current) }
            }
        }
        return chunks.isEmpty ? [text] : chunks
    }

    private func trimEntries() {
        let max = maxSubtitleLines
        if subtitleEntries.count > max {
            subtitleEntries.removeFirst(subtitleEntries.count - max)
        }
    }

    private func startExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeExpiredEntries()
            }
        }
    }

    private func removeExpiredEntries() {
        let cutoff = Date().addingTimeInterval(-subtitleExpirySeconds)
        let before = subtitleEntries.count
        subtitleEntries.removeAll { $0.timestamp < cutoff }
        if subtitleEntries.count < before {
            AppLogger.shared.log("Expired \(before - subtitleEntries.count) subtitle entries", category: .app)
        }
    }
}
