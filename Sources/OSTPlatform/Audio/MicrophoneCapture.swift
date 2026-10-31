@preconcurrency import AVFoundation
import Foundation
import OSTCore

public enum MicrophoneCaptureError: Error, Sendable {
    case permissionDenied
    case inputUnavailable
    case captureFailed
}

public actor MicrophoneCapture {
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var processingTask: Task<Void, Never>?
    private var reconfigurationTask: Task<Void, Never>?
    private var audioStream: AsyncStream<PCMChunk>?
    private var continuation: AsyncStream<PCMChunk>.Continuation?
    private var emittedSamples: Int64 = 0

    public nonisolated let failures: AsyncStream<MicrophoneCaptureError>
    private let failureContinuation: AsyncStream<MicrophoneCaptureError>.Continuation

    public init() {
        let pair = AsyncStream<MicrophoneCaptureError>.makeStream(bufferingPolicy: .bufferingNewest(1))
        failures = pair.stream
        failureContinuation = pair.continuation
    }

    public func start() async throws -> AsyncStream<PCMChunk> {
        if let audioStream, engine != nil { return audioStream }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw MicrophoneCaptureError.permissionDenied
        }
        let pair = AsyncStream<PCMChunk>.makeStream(bufferingPolicy: .bufferingNewest(8))
        audioStream = pair.stream
        continuation = pair.continuation
        do {
            try startResources()
        } catch {
            stop()
            throw error
        }
        return pair.stream
    }

    public func stop() {
        reconfigurationTask?.cancel()
        reconfigurationTask = nil
        stopResources()
        continuation?.finish()
        continuation = nil
        audioStream = nil
        emittedSamples = 0
    }

    public func suspendForSleep() {
        reconfigurationTask?.cancel()
        reconfigurationTask = nil
        stopResources()
    }

    public func resumeAfterWake() throws {
        guard audioStream != nil, engine == nil else { return }
        try startResources()
    }

    private func startResources() throws {
        guard engine == nil else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw MicrophoneCaptureError.permissionDenied
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              format.commonFormat == .pcmFormatFloat32,
              let mono = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: format.sampleRate,
                channels: 1,
                interleaved: false
              ) else {
            throw MicrophoneCaptureError.inputUnavailable
        }
        let ring = AudioSampleRingBuffer(capacity: max(Int(format.sampleRate * 10), 160_000))
        let converter = try PCMConverter(inputStreamDescription: mono.streamDescription.pointee)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            let samples = Self.monoSamples(from: buffer)
            samples.withUnsafeBufferPointer {
                if let base = $0.baseAddress { ring.write(base, count: $0.count) }
            }
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw MicrophoneCaptureError.captureFailed
        }
        self.engine = engine
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.scheduleReconfiguration() }
        }
        let continuation = continuation
        let startSample = emittedSamples
        processingTask = Task.detached(priority: .userInitiated) { [weak self] in
            var processed = startSample
            while !Task.isCancelled {
                let samples = ring.read(maxCount: 4096)
                if samples.isEmpty {
                    try? await Task.sleep(for: .milliseconds(10))
                    continue
                }
                do {
                    let converted = try converter.convert(samples)
                    guard !converted.isEmpty else { continue }
                    continuation?.yield(PCMChunk(
                        samples: converted,
                        startTime: .seconds(Double(processed) / PCMConverter.outputSampleRate)
                    ))
                    processed += Int64(converted.count)
                    await self?.setEmittedSamples(processed)
                } catch {
                    await self?.reportFailure(.captureFailed)
                    return
                }
            }
        }
    }

    private func stopResources() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        processingTask?.cancel()
        processingTask = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
    }

    private func scheduleReconfiguration() {
        guard engine != nil else { return }
        reconfigurationTask?.cancel()
        reconfigurationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await self.reconfigure()
        }
    }

    private func reconfigure() {
        stopResources()
        do {
            try startResources()
        } catch {
            reportFailure(error as? MicrophoneCaptureError ?? .captureFailed)
        }
    }

    private func reportFailure(_ error: MicrophoneCaptureError) {
        stop()
        failureContinuation.yield(error)
    }

    private func setEmittedSamples(_ value: Int64) {
        emittedSamples = value
    }

    nonisolated static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channels = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var samples = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            for channel in 0..<channelCount {
                samples[frame] += buffer.format.isInterleaved
                    ? channels[0][frame * channelCount + channel]
                    : channels[channel][frame]
            }
            samples[frame] /= Float(channelCount)
        }
        return samples
    }
}
