import Foundation
import ScreenCaptureKit
@preconcurrency import CoreMedia
import CoreGraphics

/// Errors that can occur during audio capture.
enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case noShareableContent
    case streamSetupFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording and System Audio Recording permissions are required to capture system audio. Enable OST in System Settings > Privacy & Security > Screen & System Audio Recording."
        case .noShareableContent:
            return "Could not retrieve shareable content from the system."
        case .streamSetupFailed(let underlying):
            return "Failed to set up audio stream: \(underlying.localizedDescription)"
        }
    }
}

/// Sendable wrapper for CoreMedia buffers delivered from ScreenCaptureKit callbacks.
struct AudioSampleBuffer: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
}

/// Captures system audio using ScreenCaptureKit (audio-only, no video).
final class SystemAudioCapture: NSObject, @unchecked Sendable {

    // MARK: - Private State

    private var _stream: SCStream?
    private var stream: SCStream? {
        get { stateLock.withLock { _stream } }
        set { stateLock.withLock { _stream = newValue } }
    }
    private var _continuation: AsyncStream<AudioSampleBuffer>.Continuation?
    private var continuation: AsyncStream<AudioSampleBuffer>.Continuation? {
        get { stateLock.withLock { _continuation } }
        set { stateLock.withLock { _continuation = newValue } }
    }
    private var _audioBuffers: AsyncStream<AudioSampleBuffer>?
    private var audioBuffers: AsyncStream<AudioSampleBuffer>? {
        get { stateLock.withLock { _audioBuffers } }
        set { stateLock.withLock { _audioBuffers = newValue } }
    }
    private let stateLock = NSLock()
    private var _bufferCount: Int = 0

    /// Requests permission if needed, then starts capturing system audio.
    /// Returns a fresh AsyncStream of audio buffers for each capture session.
    func startCapture() async throws -> AsyncStream<AudioSampleBuffer> {
        guard stream == nil else {
            AppLogger.post("Stream already active, returning existing", category: .audio)
            return audioBuffers ?? AsyncStream { $0.finish() }
        }

        if !CGPreflightScreenCaptureAccess() {
            AppLogger.post("Screen recording permission not yet granted; requesting access", category: .audio)
            guard CGRequestScreenCaptureAccess() else {
                throw AudioCaptureError.permissionDenied
            }
            AppLogger.post("Screen recording permission granted", category: .audio)
        }

        resetBufferCount()

        AppLogger.post("Requesting SCShareableContent...", category: .audio)
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            AppLogger.post("SCShareableContent failed: \(error.localizedDescription)", category: .error)
            if isPermissionError(error) {
                throw AudioCaptureError.permissionDenied
            }
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
        var capturedContinuation: AsyncStream<AudioSampleBuffer>.Continuation?
        let bufferStream = AsyncStream<AudioSampleBuffer> { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
        self.audioBuffers = bufferStream
        stream = newStream

        do {
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            AppLogger.post("Stream output added, starting capture...", category: .audio)
            try await newStream.startCapture()
            guard isCurrentStream(newStream) else {
                AppLogger.post("SCStream started after cancellation; stopping stale stream", category: .audio)
                throw CancellationError()
            }
            AppLogger.post("SCStream capture started successfully", category: .audio)
        } catch is CancellationError {
            AppLogger.post("SCStream start cancelled", category: .audio)
            try? await newStream.stopCapture()
            finishBufferStreamIfCurrent(newStream)
            capturedContinuation?.finish()
            throw CancellationError()
        } catch {
            AppLogger.post("SCStream start failed: \(error.localizedDescription)", category: .error)
            try? await newStream.stopCapture()
            finishBufferStreamIfCurrent(newStream)
            if isPermissionError(error) {
                throw AudioCaptureError.permissionDenied
            }
            throw AudioCaptureError.streamSetupFailed(underlying: error)
        }

        return bufferStream
    }

    /// Stops capturing system audio and finishes the async stream.
    func stopCapture() async {
        guard let current = stream else {
            finishBufferStream()
            return
        }
        stream = nil
        // Finish continuation BEFORE awaiting stopCapture to prevent dangling yields
        finishBufferStream()
        AppLogger.post("Stopping capture (received \(currentBufferCount()) audio buffers)", category: .audio)
        do {
            try await current.stopCapture()
        } catch {
            AppLogger.post("Stop error (non-fatal): \(error.localizedDescription)", category: .audio)
        }
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

    private func isPermissionError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("permission")
            || message.contains("recording")
            || message.contains("privacy")
            || message.contains("denied")
            || message.contains("not authorized")
    }

    private func resetBufferCount() {
        stateLock.withLock {
            _bufferCount = 0
        }
    }

    private func currentBufferCount() -> Int {
        stateLock.withLock { _bufferCount }
    }

    private func incrementBufferCount() -> Int {
        stateLock.withLock {
            _bufferCount += 1
            return _bufferCount
        }
    }

    private func finishBufferStream() {
        let streamContinuation = stateLock.withLock {
            let streamContinuation = _continuation
            _continuation = nil
            _audioBuffers = nil
            return streamContinuation
        }
        streamContinuation?.finish()
    }

    private func finishBufferStreamIfCurrent(_ stoppedStream: SCStream) {
        let streamContinuation: AsyncStream<AudioSampleBuffer>.Continuation? = stateLock.withLock {
            guard let current = _stream, current === stoppedStream else {
                return nil
            }
            _stream = nil
            let streamContinuation = _continuation
            _continuation = nil
            _audioBuffers = nil
            return streamContinuation
        }
        streamContinuation?.finish()
    }

    private func isCurrentStream(_ candidate: SCStream) -> Bool {
        stateLock.withLock {
            guard let current = _stream else { return false }
            return current === candidate
        }
    }

    private func continuationIfCurrent(_ outputStream: SCStream) -> AsyncStream<AudioSampleBuffer>.Continuation? {
        stateLock.withLock {
            guard let current = _stream, current === outputStream else { return nil }
            return _continuation
        }
    }
}

// MARK: - SCStreamDelegate

extension SystemAudioCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        AppLogger.post("SCStream stopped with error: \(error.localizedDescription)", category: .error)
        finishBufferStreamIfCurrent(stream)
    }
}

// MARK: - SCStreamOutput

extension SystemAudioCapture: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard let streamContinuation = continuationIfCurrent(stream) else { return }
        guard type == .audio else { return }
        guard sampleBuffer.isValid else {
            AppLogger.post("Received invalid audio buffer", category: .audio)
            return
        }
        let count = incrementBufferCount()
        if count == 1 {
            // Log audio format details on first buffer for diagnostics
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                let desc = asbd.pointee
                AppLogger.post("Audio format: \(desc.mSampleRate)Hz, \(desc.mChannelsPerFrame)ch, \(desc.mBitsPerChannel)bit, formatID=\(desc.mFormatID)", category: .audio)
            }
        }
        if count <= 3 || count % 100 == 0 {
            AppLogger.post("Audio buffer #\(count) received", category: .audio)
        }
        streamContinuation.yield(AudioSampleBuffer(sampleBuffer: sampleBuffer))
    }
}
