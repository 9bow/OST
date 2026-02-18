import Foundation
import ScreenCaptureKit
import CoreMedia
import AVFoundation

/// Errors that can occur during audio capture.
enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case noShareableContent
    case streamSetupFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission is required to capture system audio. Enable it in System Settings > Privacy & Security > Screen Recording."
        case .noShareableContent:
            return "Could not retrieve shareable content from the system."
        case .streamSetupFailed(let underlying):
            return "Failed to set up audio stream: \(underlying.localizedDescription)"
        }
    }
}

/// Captures system audio using ScreenCaptureKit (audio-only, no video).
final class SystemAudioCapture: NSObject, @unchecked Sendable {

    // MARK: - Private State

    private var stream: SCStream?
    private var continuation: AsyncStream<CMSampleBuffer>.Continuation?
    private(set) var audioBuffers: AsyncStream<CMSampleBuffer>?
    private var bufferCount: Int = 0

    /// Requests permission if needed, then starts capturing system audio.
    /// Returns a fresh AsyncStream of audio buffers for each capture session.
    func startCapture() async throws -> AsyncStream<CMSampleBuffer> {
        guard stream == nil else {
            AppLogger.post("Stream already active, returning existing", category: .audio)
            return audioBuffers!
        }

        bufferCount = 0

        AppLogger.post("Requesting SCShareableContent...", category: .audio)
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            AppLogger.post("SCShareableContent failed: \(error.localizedDescription)", category: .error)
            throw AudioCaptureError.noShareableContent
        }

        AppLogger.post("Displays: \(content.displays.count), Apps: \(content.applications.count), Windows: \(content.windows.count)", category: .audio)

        guard !content.displays.isEmpty else {
            AppLogger.post("No displays found", category: .error)
            throw AudioCaptureError.noShareableContent
        }

        let display = content.displays[0]
        AppLogger.post("Using display: \(display.width)x\(display.height)", category: .audio)

        // Audio-only filter: include all windows on the primary display.
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = makeConfiguration()

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)

        // Create a fresh stream for each capture session.
        var capturedContinuation: AsyncStream<CMSampleBuffer>.Continuation?
        let bufferStream = AsyncStream<CMSampleBuffer> { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
        self.audioBuffers = bufferStream

        do {
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            AppLogger.post("Stream output added, starting capture...", category: .audio)
            try await newStream.startCapture()
            AppLogger.post("SCStream capture started successfully", category: .audio)
        } catch {
            AppLogger.post("SCStream start failed: \(error.localizedDescription)", category: .error)
            self.continuation = nil
            self.audioBuffers = nil
            throw AudioCaptureError.streamSetupFailed(underlying: error)
        }

        stream = newStream
        return bufferStream
    }

    /// Stops capturing system audio and finishes the async stream.
    func stopCapture() async {
        guard let current = stream else { return }
        stream = nil
        AppLogger.post("Stopping capture (received \(bufferCount) audio buffers)", category: .audio)
        do {
            try await current.stopCapture()
        } catch {
            AppLogger.post("Stop error (non-fatal): \(error.localizedDescription)", category: .audio)
        }
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Helpers

    private func makeConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()

        // Audio settings.
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000
        config.channelCount = 1

        // Minimize video overhead — we only need audio.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps max
        config.showsCursor = false

        AppLogger.post("Audio config: \(config.sampleRate)Hz, \(config.channelCount)ch", category: .audio)

        return config
    }
}

// MARK: - SCStreamDelegate

extension SystemAudioCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        AppLogger.post("SCStream stopped with error: \(error.localizedDescription)", category: .error)
        continuation?.finish()
        continuation = nil
        self.stream = nil
    }
}

// MARK: - SCStreamOutput

extension SystemAudioCapture: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid else {
            AppLogger.post("Received invalid audio buffer", category: .audio)
            return
        }
        bufferCount += 1
        if bufferCount == 1 {
            // Log audio format details on first buffer for diagnostics
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                let desc = asbd.pointee
                AppLogger.post("Audio format: \(desc.mSampleRate)Hz, \(desc.mChannelsPerFrame)ch, \(desc.mBitsPerChannel)bit, formatID=\(desc.mFormatID)", category: .audio)
            }
        }
        if bufferCount <= 3 || bufferCount % 100 == 0 {
            AppLogger.post("Audio buffer #\(bufferCount) received", category: .audio)
        }
        continuation?.yield(sampleBuffer)
    }
}
