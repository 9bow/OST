import Foundation
import SwiftUI
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
    @Published private(set) var liveTranslatedText: String = ""
    @Published private(set) var isStartingCapture: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Pipeline Components

    private let audioCapture = SystemAudioCapture()
    private let speechRecognizer: SpeechRecognizer
    let translationService = TranslationService()
    let sessionRecorder: SessionRecorder

    // MARK: - Private State

    private var bufferConsumerTask: Task<Void, Never>?
    private var expiryTimer: Timer?
    private var speechPauseTimer: Timer?
    private var liveTranslationTimer: Timer?
    private var liveTranslationTask: Task<Void, Never>?
    private var lastConsumedPartial: String = ""
    private var lastConsumedTail: String = ""
    private var lastSinkCurrentText: String = ""
    private var saveSessionHistory: Bool = true
    private var cancellables = Set<AnyCancellable>()
    private var autoDetectEnabled: Bool = false
    private var hasDetectedLanguage: Bool = false
    private var autoDetectGeneration: Int = 0
    @Published private(set) var detectedLanguage: SupportedLanguage?
    var onCaptureStoppedWithError: (() -> Void)?

    // Settings reference for expiry/max lines
    var maxSubtitleLines: Int = 3
    var subtitleExpirySeconds: Double = 20
    var speechPauseSeconds: Double = 3.0

    // MARK: - Init

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.speechRecognizer = SpeechRecognizer(locale: locale)
        self.sessionRecorder = SessionRecorder()
        setupTextBindings()
    }

    init(locale: Locale = Locale(identifier: "en-US"), sessionRecorder: SessionRecorder) {
        self.speechRecognizer = SpeechRecognizer(locale: locale)
        self.sessionRecorder = sessionRecorder
        setupTextBindings()
    }

    // MARK: - Public Interface

    /// Starts system audio capture and speech recognition.
    func startCapture(saveSession: Bool = true, useOnDevice: Bool = true) async {
        guard !isCapturing else { return }
        guard isStartingCapture else { return }
        errorMessage = nil
        saveSessionHistory = saveSession
        resetDisplayStateForNewCapture()

        AppLogger.shared.log("Starting capture...", category: .app)

        do {
            AppLogger.shared.log("Requesting speech recognition authorization", category: .speech)
            try await speechRecognizer.startRecognition(useOnDevice: useOnDevice)
            guard isStartingCapture else {
                speechRecognizer.stopRecognition()
                finishStartingCapture()
                return
            }
            AppLogger.shared.log("Speech recognition started", category: .speech)

            AppLogger.shared.log("Starting audio capture", category: .audio)
            let buffers = try await audioCapture.startCapture()
            guard isStartingCapture else {
                speechRecognizer.stopRecognition()
                await audioCapture.stopCapture()
                finishStartingCapture()
                return
            }
            AppLogger.shared.log("Audio capture started", category: .audio)

            isCapturing = true
            startConsumingBuffers(from: buffers)
            startExpiryTimer()

            if saveSession {
                sessionRecorder.startSession()
            }
            finishStartingCapture()
        } catch {
            if !isStartingCapture || error is CancellationError {
                AppLogger.shared.log("Capture start cancelled", category: .app)
                speechRecognizer.stopRecognition()
                await audioCapture.stopCapture()
                finishStartingCapture()
                return
            }
            AppLogger.shared.log("Capture failed: \(error.localizedDescription)", category: .error)
            errorMessage = error.localizedDescription
            speechRecognizer.stopRecognition()
            await audioCapture.stopCapture()
            finishStartingCapture()
            return
        }
    }

    func beginStartingCapture() -> Bool {
        guard !isCapturing, !isStartingCapture else { return false }
        isStartingCapture = true
        return true
    }

    func finishStartingCapture() {
        isStartingCapture = false
    }

    /// Stops capture and recognition, preserving last recognized text.
    func stopCapture() async {
        let wasStartingCapture = isStartingCapture
        finishStartingCapture()
        guard isCapturing || wasStartingCapture else { return }
        if isCapturing {
            consumeRemainingText()
            isCapturing = false
        }

        bufferConsumerTask?.cancel()
        bufferConsumerTask = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
        speechPauseTimer?.invalidate()
        speechPauseTimer = nil
        liveTranslationTimer?.invalidate()
        liveTranslationTimer = nil
        liveTranslationTask?.cancel()
        liveTranslationTask = nil
        liveTranslatedText = ""

        speechRecognizer.stopRecognition()
        await audioCapture.stopCapture()

        if sessionRecorder.currentSession != nil {
            sessionRecorder.endSession()
        }
        AppLogger.shared.log("Capture stopped", category: .app)
    }

    func clearError() {
        errorMessage = nil
    }

    func updateSubtitleSettings(maxLines: Double, expirySeconds: Double, pauseSeconds: Double) {
        maxSubtitleLines = clampedInt(maxLines, min: 1, max: 10, fallback: 3)
        subtitleExpirySeconds = clampedDouble(expirySeconds, min: 3, max: 60, fallback: 20)
        speechPauseSeconds = clampedDouble(pauseSeconds, min: 0.5, max: 5, fallback: 3)
        removeExpiredEntries()
        trimEntries()
    }

    func updateSessionHistoryRecording(enabled: Bool) {
        saveSessionHistory = enabled
        guard isCapturing else { return }

        if enabled {
            if sessionRecorder.currentSession == nil {
                sessionRecorder.startSession()
            }
        } else if sessionRecorder.currentSession != nil {
            sessionRecorder.endSession()
        }
    }

    func clearVisibleTranslationsForLanguageChange() {
        liveTranslationTimer?.invalidate()
        liveTranslationTimer = nil
        liveTranslationTask?.cancel()
        liveTranslationTask = nil
        liveTranslatedText = ""

        let visibleEntryIDs = subtitleEntries.map(\.id)
        for index in subtitleEntries.indices {
            subtitleEntries[index].translated = ""
        }
        sessionRecorder.clearCurrentTranslations(ids: visibleEntryIDs)
    }

    func refreshVisibleTranslationsForLanguageChange() {
        let entriesToTranslate = subtitleEntries.map { (id: $0.id, text: $0.recognized) }
        let shouldUpdateSessionHistory = sessionRecorder.currentSession != nil
        for entry in entriesToTranslate where !entry.text.isEmpty {
            translateEntry(
                id: entry.id,
                text: entry.text,
                recordSessionEntry: false,
                updateSessionHistory: shouldUpdateSessionHistory,
                updateCurrentSessionOnly: true
            )
        }
        debounceLiveTranslation()
    }

    private func clampedInt(_ value: Double, min: Int, max: Int, fallback: Int) -> Int {
        guard value.isFinite else { return fallback }
        return Swift.min(max, Swift.max(min, Int(value)))
    }

    private func clampedDouble(_ value: Double, min: Double, max: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(max, Swift.max(min, value))
    }

    private func resetDisplayStateForNewCapture() {
        lastConsumedPartial = ""
        lastConsumedTail = ""
        lastSinkCurrentText = ""
        subtitleEntries = []
        liveText = ""
        liveTranslatedText = ""
    }

    /// Changes the speech recognition language.
    func changeSourceLanguage(to locale: Locale, useOnDevice: Bool = true) async {
        do {
            try await speechRecognizer.changeLanguage(locale: locale, useOnDevice: useOnDevice)
            lastConsumedPartial = ""
            lastConsumedTail = ""
        } catch {
            errorMessage = error.localizedDescription
            if isCapturing {
                await stopCapture()
            }
        }
    }

    /// Enables automatic language detection from initial speech.
    func enableAutoDetect() {
        autoDetectGeneration += 1
        autoDetectEnabled = true
        hasDetectedLanguage = false
        detectedLanguage = nil
    }

    func disableAutoDetect() {
        autoDetectGeneration += 1
        autoDetectEnabled = false
        hasDetectedLanguage = false
        detectedLanguage = nil
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
        let detectionGeneration = autoDetectGeneration
        hasDetectedLanguage = true
        detectedLanguage = target

        AppLogger.shared.log("Auto-detected language: \(target.displayName) (confidence: \(confidence))", category: .speech)

        Task {
            guard self.isCapturing,
                  self.autoDetectEnabled,
                  self.autoDetectGeneration == detectionGeneration else { return }
            // Reset consumed state BEFORE language change to avoid stale tracking
            lastConsumedPartial = ""
            lastConsumedTail = ""
            liveText = ""
            await changeSourceLanguage(to: target.speechLocale, useOnDevice: speechRecognizer.currentOnDeviceSetting)
            if self.errorMessage != nil {
                self.onCaptureStoppedWithError?()
                return
            }
            // Reconfigure translation source language to match detected language
            guard self.isCapturing,
                  self.errorMessage == nil,
                  self.autoDetectEnabled,
                  self.autoDetectGeneration == detectionGeneration else { return }
            if let currentTarget = translationService.targetLanguage {
                clearVisibleTranslationsForLanguageChange()
                translationService.configure(source: target.translationLocale, target: currentTarget)
                _ = await translationService.waitForSessionReady(timeout: 1.0)
                guard self.isCapturing,
                      self.errorMessage == nil,
                      self.autoDetectEnabled,
                      self.autoDetectGeneration == detectionGeneration else { return }
                refreshVisibleTranslationsForLanguageChange()
            }
        }
    }

    // MARK: - Private Helpers

    private func startConsumingBuffers(from buffers: AsyncStream<AudioSampleBuffer>) {
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
                self.speechRecognizer.append(buffer.sampleBuffer)
            }
            AppLogger.shared.log("Buffer consumer ended after \(count) buffers", category: .audio)
            if !Task.isCancelled && self.isCapturing {
                self.errorMessage = "Audio capture stopped unexpectedly."
                await self.stopCapture()
                self.onCaptureStoppedWithError?()
            }
        }
    }

    private func setupTextBindings() {
        speechRecognizer.$currentText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentText in
                guard let self else { return }

                // Handle recognizer restart (currentText cleared) BEFORE updating liveText
                if currentText.isEmpty {
                    let previousText = self.lastSinkCurrentText
                    if !self.liveText.isEmpty {
                        self.consumeRemainingText()
                        self.lastConsumedPartial = previousText
                    }
                    if !self.lastConsumedPartial.isEmpty {
                        // Save tail of consumed text for overlap detection on next session.
                        self.lastConsumedTail = String(self.lastConsumedPartial.suffix(60))
                    }
                    self.lastConsumedPartial = ""
                    self.lastSinkCurrentText = ""
                    self.liveText = ""
                    self.liveTranslatedText = ""
                    self.liveTranslationTimer?.invalidate()
                    self.liveTranslationTask?.cancel()
                    self.speechPauseTimer?.invalidate()
                    self.speechPauseTimer = nil
                    return
                }

                // Show only the unconsumed portion as live text
                if !self.lastConsumedPartial.isEmpty && currentText.hasPrefix(self.lastConsumedPartial) {
                    let tail = String(currentText.dropFirst(self.lastConsumedPartial.count)).trimmingCharacters(in: .whitespaces)
                    self.liveText = self.stripLeadingPunctuation(tail)
                } else if self.lastConsumedPartial.isEmpty {
                    // After restart, check for overlap with previous session's tail
                    if !self.lastConsumedTail.isEmpty {
                        let stripped = self.stripOverlap(newText: currentText, tail: self.lastConsumedTail)
                        self.liveText = self.stripLeadingPunctuation(stripped)
                        if stripped != currentText {
                            // We found overlap; track what we've consumed from the new session
                            let overlapLength = currentText.count - stripped.count
                            self.lastConsumedPartial = String(currentText.prefix(overlapLength))
                            self.lastConsumedTail = ""
                            AppLogger.shared.log("Stripped overlap: \(overlapLength) chars from new session", category: .speech)
                        } else if currentText.count >= self.lastConsumedTail.count {
                            self.lastConsumedTail = ""
                        }
                    } else {
                        self.liveText = self.stripLeadingPunctuation(currentText)
                    }
                } else {
                    // currentText diverged from lastConsumedPartial (recognizer reformulation)
                    // Find longest common prefix to avoid re-showing already-consumed text
                    let common = self.findCommonPrefix(currentText, self.lastConsumedPartial)
                    if common.count > 10 {
                        self.lastConsumedPartial = common
                        let tail = String(currentText.dropFirst(common.count)).trimmingCharacters(in: .whitespaces)
                        self.liveText = self.stripLeadingPunctuation(tail)
                    } else {
                        // Check if consumed text reappears at the END of reformulated text
                        // (recognizer prepended new content before already-consumed text)
                        let trimmedConsumed = self.lastConsumedPartial.trimmingCharacters(in: .whitespaces)
                        let trimmedCurrent = currentText.trimmingCharacters(in: .whitespaces)
                        if !trimmedConsumed.isEmpty && trimmedCurrent.hasSuffix(trimmedConsumed) {
                            let newPart = String(trimmedCurrent.dropLast(trimmedConsumed.count))
                            self.liveText = self.stripLeadingPunctuation(newPart)
                            // Do NOT update lastConsumedPartial here: newPart is still live/unconsumed.
                            // Overwriting with currentText would cause newPart to be silently dropped
                            // on the next sink call when currentText extends.
                            AppLogger.shared.log("Reformulation suffix stripped: \(trimmedConsumed.count) chars", category: .speech)
                        } else {
                            // Completely different text (e.g. language change)
                            self.lastConsumedPartial = ""
                            self.liveText = self.stripLeadingPunctuation(currentText)
                        }
                    }
                }

                self.lastSinkCurrentText = currentText
                self.detectLanguageIfNeeded(currentText)
                // Extract completed sentences immediately (triggered by punctuation)
                // Pass currentText from sink to avoid reading stale speechRecognizer.currentText
                self.extractCompleteSentences(sinkCurrentText: currentText)
                self.resetSpeechPauseTimer()
                self.debounceLiveTranslation()
            }
            .store(in: &cancellables)

        speechRecognizer.$recognitionError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self, let error else { return }
                AppLogger.shared.log("Recognition stopped after retries: \(error.localizedDescription)", category: .error)
                self.errorMessage = error.localizedDescription
                if self.isCapturing {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        await self.stopCapture()
                        self.onCaptureStoppedWithError?()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func debounceLiveTranslation() {
        liveTranslationTimer?.invalidate()
        guard !liveText.isEmpty else {
            liveTranslatedText = ""
            liveTranslationTask?.cancel()
            return
        }
        liveTranslationTimer = Self.scheduledCommonTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCapturing, !self.liveText.isEmpty else { return }
                let textToTranslate = self.liveText
                let generation = self.translationService.configurationGeneration
                self.liveTranslationTask?.cancel()
                self.liveTranslationTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        let result = try await self.translationService.translate(textToTranslate, generation: generation)
                        if !Task.isCancelled && self.liveText == textToTranslate {
                            self.liveTranslatedText = result
                        }
                    } catch TranslationServiceError.staleConfiguration {
                        return
                    } catch is CancellationError {
                        return
                    } catch {
                        AppLogger.shared.log("Live translation failed: \(error.localizedDescription)", category: .error)
                    }
                }
            }
        }
    }

    private func resetSpeechPauseTimer() {
        speechPauseTimer?.invalidate()
        speechPauseTimer = Self.scheduledCommonTimer(withTimeInterval: speechPauseSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handlePartialTextStabilized()
            }
        }
    }

    /// When partial recognition text hasn't changed for the configured pause duration, consume it.
    private func handlePartialTextStabilized() {
        guard !liveText.isEmpty, isCapturing else { return }

        let text = liveText
        liveText = ""
        liveTranslatedText = ""
        lastConsumedPartial = lastSinkCurrentText

        AppLogger.shared.log("Pause-triggered consume: \"\(text)\"", category: .speech)

        let chunks = splitIntoChunks(text)
        for sentence in chunks {
            let cleaned = stripLeadingPunctuation(sentence)
            guard !isPunctuationOnly(cleaned), !isDuplicateEntry(cleaned) else { continue }
            let entry = SubtitleEntry(timestamp: Date(), recognized: cleaned, isFinal: true)
            subtitleEntries.append(entry)
            translateEntry(id: entry.id, text: cleaned)
        }
        trimEntries()
    }

    /// Extracts completed sentences from liveText when punctuation boundaries are detected.
    /// Uses `sinkCurrentText` (the value delivered by the Combine sink) instead of reading
    /// `speechRecognizer.currentText` directly, which may have changed since delivery.
    private func extractCompleteSentences(sinkCurrentText: String) {
        guard !liveText.isEmpty, isCapturing else { return }

        // Split liveText into sentences using linguistic analysis
        var sentenceRanges: [Range<String.Index>] = []
        liveText.enumerateSubstrings(in: liveText.startIndex..., options: .bySentences) { _, range, _, _ in
            sentenceRanges.append(range)
        }

        // Need 2+ sentences: all but last are complete, last is in-progress
        guard sentenceRanges.count >= 2, let lastRange = sentenceRanges.last else { return }

        let lastStart = lastRange.lowerBound
        let completedText = String(liveText[..<lastStart])
        let remaining = String(liveText[lastStart...]).trimmingCharacters(in: .whitespaces)

        // Extract individual sentences from the completed portion
        var sentences: [String] = []
        completedText.enumerateSubstrings(in: completedText.startIndex..., options: .bySentences) { sub, _, _, _ in
            if let s = sub?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
                sentences.append(s)
            }
        }
        guard !sentences.isEmpty else { return }

        for sentence in sentences {
            let cleaned = stripLeadingPunctuation(sentence)
            guard !isPunctuationOnly(cleaned), !isDuplicateEntry(cleaned) else { continue }
            let entry = SubtitleEntry(timestamp: Date(), recognized: cleaned, isFinal: true)
            subtitleEntries.append(entry)
            translateEntry(id: entry.id, text: cleaned)
        }
        trimEntries()

        // Update tracking using the consistent sinkCurrentText value
        if remaining.isEmpty {
            lastConsumedPartial = sinkCurrentText
        } else if let range = sinkCurrentText.range(of: remaining, options: .backwards) {
            lastConsumedPartial = String(sinkCurrentText[..<range.lowerBound])
        } else {
            lastConsumedPartial = sinkCurrentText
        }

        liveText = remaining
        resetSpeechPauseTimer()
        AppLogger.shared.log("Sentence-triggered: extracted \(sentences.count) sentence(s)", category: .speech)
    }

    /// Consumes any remaining live text into subtitle entries when the recognizer restarts.
    private func consumeRemainingText() {
        guard !liveText.isEmpty, isCapturing else { return }
        let text = liveText
        liveText = ""
        AppLogger.shared.log("Consuming remaining text before reset: \"\(text)\"", category: .speech)
        let chunks = splitIntoChunks(text)
        for sentence in chunks {
            let cleaned = stripLeadingPunctuation(sentence)
            guard !isPunctuationOnly(cleaned), !isDuplicateEntry(cleaned) else { continue }
            let entry = SubtitleEntry(timestamp: Date(), recognized: cleaned, isFinal: true)
            subtitleEntries.append(entry)
            translateEntry(id: entry.id, text: cleaned)
        }
        trimEntries()
    }

    /// Translates a subtitle entry individually.
    private func translateEntry(
        id: UUID,
        text: String,
        recordSessionEntry: Bool = true,
        updateSessionHistory: Bool = true,
        updateCurrentSessionOnly: Bool = false
    ) {
        if recordSessionEntry && saveSessionHistory {
            sessionRecorder.record(id: id, recognized: text, translated: "")
        }

        let generation = translationService.configurationGeneration
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.translationService.translate(text, generation: generation)
                if let idx = self.subtitleEntries.firstIndex(where: { $0.id == id }) {
                    self.subtitleEntries[idx].translated = result
                    AppLogger.shared.log("Translated: \(text) → \(result)", category: .translation)
                }
                if updateSessionHistory {
                    if updateCurrentSessionOnly {
                        self.sessionRecorder.updateCurrentTranslation(id: id, translated: result)
                    } else {
                        self.sessionRecorder.updateTranslation(id: id, translated: result)
                    }
                }
            } catch TranslationServiceError.staleConfiguration {
                return
            } catch is CancellationError {
                return
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
                for wordSubstring in sentence.split(separator: " ") {
                    let word = String(wordSubstring)
                    if word.count > maxChars {
                        if !current.isEmpty {
                            chunks.append(current)
                            current = ""
                        }
                        chunks.append(contentsOf: splitLongToken(word, maxChars: maxChars))
                        continue
                    }
                    let candidate = current.isEmpty ? word : current + " " + word
                    if candidate.count > maxChars && !current.isEmpty {
                        chunks.append(current)
                        current = word
                    } else {
                        current = candidate
                    }
                }
                if !current.isEmpty { chunks.append(current) }
            }
        }
        return chunks.isEmpty ? [text] : chunks
    }

    private func splitLongToken(_ text: String, maxChars: Int) -> [String] {
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maxChars, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end]))
            start = end
        }
        return chunks
    }

    /// Returns the longest common prefix between two strings.
    private func findCommonPrefix(_ a: String, _ b: String) -> String {
        var endIndex = a.startIndex
        var aIdx = a.startIndex
        var bIdx = b.startIndex
        while aIdx < a.endIndex && bIdx < b.endIndex {
            if a[aIdx] != b[bIdx] { break }
            aIdx = a.index(after: aIdx)
            bIdx = b.index(after: bIdx)
            endIndex = aIdx
        }
        return String(a[..<endIndex])
    }

    /// Strips leading punctuation characters (commas, periods, etc.) and all leading whitespace (including newlines) from text.
    private func stripLeadingPunctuation(_ text: String) -> String {
        var result = text[...]
        while let first = result.unicodeScalars.first,
              CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines).contains(first) {
            result = result.dropFirst()
        }
        return String(result)
    }

    /// Returns true if text is only punctuation/whitespace and should not be a subtitle entry.
    private func isPunctuationOnly(_ text: String) -> Bool {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return stripped.isEmpty
    }

    /// Checks if the same recognized text was very recently added to avoid duplicates from recognizer reformulation.
    private func isDuplicateEntry(_ text: String) -> Bool {
        let cutoff = Date().addingTimeInterval(-2.0)
        return subtitleEntries.suffix(2).contains { $0.recognized == text && $0.timestamp > cutoff }
    }

    /// Finds and strips overlapping text between the tail of previously consumed text and the start of new text.
    private func stripOverlap(newText: String, tail: String) -> String {
        // Try progressively shorter suffixes of the tail to find overlap with the start of newText
        let tailWords = tail.split(separator: " ")
        for startIdx in 0..<tailWords.count {
            let suffix = tailWords[startIdx...].joined(separator: " ")
            guard suffix.count >= 4 else { continue }
            if newText.hasPrefix(suffix) {
                return String(newText.dropFirst(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return stripCharacterOverlap(newText: newText, tail: tail)
    }

    private func stripCharacterOverlap(newText: String, tail: String) -> String {
        // Fallback for CJK and URL-like text where word boundaries are not useful.
        let maxOverlap = Swift.min(tail.count, newText.count)
        guard maxOverlap >= 4 else { return newText }

        var overlapLength = maxOverlap
        while overlapLength >= 4 {
            let suffix = String(tail.suffix(overlapLength))
            if newText.hasPrefix(suffix) {
                return String(newText.dropFirst(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
            overlapLength -= 1
        }
        return newText
    }

    private func trimEntries() {
        let max = maxSubtitleLines
        if subtitleEntries.count > max {
            subtitleEntries.removeFirst(subtitleEntries.count - max)
        }
    }

    private func startExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = Self.scheduledCommonTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeExpiredEntries()
            }
        }
    }

    private static func scheduledCommonTimer(
        withTimeInterval interval: TimeInterval,
        repeats: Bool,
        block: @escaping @Sendable (Timer) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
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
