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
final class SpeechRecognizer: ObservableObject {

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

    var currentOnDeviceSetting: Bool { useOnDevice }

    // MARK: - Init

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.currentLocale = locale
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Public Interface

    /// Requests authorization if needed, then begins recognition.
    func startRecognition(useOnDevice: Bool = true) async throws {
        try await requestAuthorization()
        self.useOnDevice = useOnDevice
        self.isActive = true
        try beginRecognitionTask()
    }

    /// Stops recognition and clears volatile state.
    func stopRecognition() {
        isActive = false
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        currentText = ""
    }

    // MARK: - Recognition Task

    private func beginRecognitionTask() throws {
        guard let recognizer, recognizer.isAvailable else {
            AppLogger.shared.log("Speech recognizer unavailable for locale: \(currentLocale.identifier)", category: .error)
            throw SpeechRecognizerError.recognizerUnavailable
        }

        // Clean up previous task without clearing isActive
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if useOnDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = true
        recognitionRequest = request

        AppLogger.shared.log("Starting recognition task (onDevice: \(useOnDevice))", category: .speech)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    let text = result.bestTranscription.formattedString
                    self.currentText = text
                    if result.isFinal {
                        AppLogger.shared.log("Final: \"\(text)\"", category: .speech)
                        self.finalizedText += (self.finalizedText.isEmpty ? "" : " ") + text
                        self.currentText = ""
                        // Auto-restart recognition for continuous listening
                        self.restartRecognition()
                    }
                }
            }
            if let error {
                Task { @MainActor in
                    AppLogger.shared.log("Recognition error: \(error.localizedDescription)", category: .error)
                    self.currentText = ""
                    // Auto-restart on transient errors
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
        } catch {
            AppLogger.shared.log("Restart failed: \(error.localizedDescription)", category: .error)
            recognitionError = error
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
