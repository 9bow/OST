import Foundation
import Speech
import CoreMedia

/// Errors that can occur during speech recognition.
enum SpeechRecognizerError: LocalizedError {
    case notAuthorized(SFSpeechRecognizerAuthorizationStatus)
    case recognizerUnavailable
    case recognitionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let status):
            switch status {
            case .denied:
                return "Speech recognition permission was denied. Enable it in System Settings > Privacy & Security > Speech Recognition."
            case .restricted:
                return "Speech recognition is restricted on this device."
            default:
                return "Speech recognition is not authorized."
            }
        case .recognizerUnavailable:
            return "Speech recognizer is not available for the selected language."
        case .recognitionFailed(let underlying):
            return "Speech recognition failed: \(underlying.localizedDescription)"
        }
    }
}

/// Wraps SFSpeechRecognizer to perform on-device speech recognition from CMSampleBuffer input.
@MainActor
final class SpeechRecognizer: NSObject, ObservableObject, SFSpeechRecognizerDelegate {

    // MARK: - Published State

    /// Partial recognition result updated continuously while speaking.
    @Published private(set) var currentText: String = ""

    /// Finalized recognition result appended when a segment is confirmed.
    @Published private(set) var finalizedText: String = ""

    /// Error from the recognition task, if any.
    @Published private(set) var recognitionError: Error?

    // MARK: - Private State

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var currentLocale: Locale
    private(set) var useOnDevice: Bool = true
    private var isActive: Bool = false
    private var taskGeneration: Int = 0
    private var taskCycleCount: Int = 0
    private var restartRetryCount: Int = 0
    private static let maxCyclesBeforeRecreate = 5
    private static let maxRestartRetries = 3

    var currentOnDeviceSetting: Bool { useOnDevice }

    // MARK: - Init

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.currentLocale = locale
        super.init()
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.recognizer?.delegate = self
    }

    // MARK: - SFSpeechRecognizerDelegate

    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer,
                                       availabilityDidChange available: Bool) {
        Task { @MainActor in
            if available && self.isActive && self.recognitionTask == nil {
                AppLogger.shared.log("Recognizer became available, restarting", category: .speech)
                self.restartRecognition()
            } else if !available {
                AppLogger.shared.log("Recognizer became unavailable", category: .speech)
            }
        }
    }

    // MARK: - Public Interface

    /// Requests authorization if needed, then begins recognition.
    func startRecognition(useOnDevice: Bool = true) async throws {
        try await requestAuthorization()
        self.useOnDevice = useOnDevice
        self.isActive = true
        self.taskCycleCount = 0
        try beginRecognitionTask()
    }

    /// Stops recognition and clears volatile state.
    func stopRecognition() {
        isActive = false
        taskGeneration += 1
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        currentText = ""
        finalizedText = ""
    }

    // MARK: - Recognition Task

    private func beginRecognitionTask() throws {
        // Periodically recreate recognizer to prevent resource exhaustion
        taskCycleCount += 1
        if taskCycleCount > Self.maxCyclesBeforeRecreate {
            AppLogger.shared.log("Recreating recognizer after \(taskCycleCount - 1) cycles", category: .speech)
            recognizer = SFSpeechRecognizer(locale: currentLocale)
            recognizer?.delegate = self
            taskCycleCount = 1
        }

        guard let recognizer, recognizer.isAvailable else {
            AppLogger.shared.log("Speech recognizer unavailable for locale: \(currentLocale.identifier)", category: .error)
            throw SpeechRecognizerError.recognizerUnavailable
        }

        // Create the new request BEFORE cleaning up the old one
        // to minimize the window where recognitionRequest is nil
        // and audio buffers from startConsumingBuffers are lost.
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if useOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = true

        // Now clean up previous task
        let oldRequest = recognitionRequest
        let oldTask = recognitionTask
        recognitionRequest = request  // Swap immediately so append() uses new request

        oldRequest?.endAudio()
        oldTask?.cancel()

        // Increment generation so stale callbacks from cancelled tasks are ignored
        taskGeneration += 1
        let generation = taskGeneration

        AppLogger.shared.log("Starting recognition task (onDevice: \(useOnDevice), cycle: \(taskCycleCount))", category: .speech)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                // Ignore callbacks from old/cancelled tasks
                guard self.taskGeneration == generation else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.currentText = text
                    if result.isFinal {
                        AppLogger.shared.log("Final: \"\(text)\"", category: .speech)
                        self.finalizedText = ""
                        self.currentText = ""
                        self.restartRecognition()
                        return
                    }
                    // Partial result with concurrent error — task is dying
                    if error != nil {
                        AppLogger.shared.log("Partial result with error, restarting", category: .speech)
                        self.restartRecognition()
                        return
                    }
                }
                if let error, result == nil {
                    AppLogger.shared.log("Recognition error: \(error.localizedDescription)", category: .error)
                    self.currentText = ""
                    self.restartRecognition()
                }
            }
        }
    }

    /// Restarts recognition if still active (called after isFinal or error).
    private func restartRecognition() {
        guard isActive else { return }
        AppLogger.shared.log("Restarting recognition...", category: .speech)
        do {
            try beginRecognitionTask()
            restartRetryCount = 0
        } catch {
            restartRetryCount += 1
            if restartRetryCount <= Self.maxRestartRetries {
                AppLogger.shared.log("Restart failed (attempt \(restartRetryCount)/\(Self.maxRestartRetries)), retrying in 2s: \(error.localizedDescription)", category: .error)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.restartRecognition()
                }
            } else {
                AppLogger.shared.log("Restart failed after \(Self.maxRestartRetries) attempts: \(error.localizedDescription)", category: .error)
                recognitionError = error
            }
        }
    }

    /// Feeds a CMSampleBuffer from the audio capture pipeline into the recognizer.
    func append(_ sampleBuffer: CMSampleBuffer) {
        recognitionRequest?.appendAudioSampleBuffer(sampleBuffer)
    }

    /// Recreates the recognizer with a new locale and restarts recognition if active.
    func changeLanguage(locale: Locale, useOnDevice: Bool = true) async throws {
        let wasRecognizing = recognitionTask != nil
        stopRecognition()
        currentLocale = locale
        recognizer = SFSpeechRecognizer(locale: locale)
        recognizer?.delegate = self
        finalizedText = ""
        if wasRecognizing {
            try await startRecognition(useOnDevice: useOnDevice)
        }
    }

    // MARK: - Authorization

    private func requestAuthorization() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized else {
            throw SpeechRecognizerError.notAuthorized(status)
        }
    }
}
