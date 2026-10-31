@preconcurrency import AVFoundation
@testable import OSTPlatform
import Testing

@Test(arguments: [false, true]) func microphoneStereoDownmixPreservesFrames(interleaved: Bool) throws {
    let format = try #require(AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: interleaved
    ))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
    buffer.frameLength = 4_800
    let channels = try #require(buffer.floatChannelData)
    for frame in 0..<4_800 {
        if interleaved {
            channels[0][frame * 2] = 0.2
            channels[0][frame * 2 + 1] = 0.6
        } else {
            channels[0][frame] = 0.2
            channels[1][frame] = 0.6
        }
    }
    let mono = MicrophoneCapture.monoSamples(from: buffer)
    #expect(mono.count == 4_800)
    #expect(mono.allSatisfy { abs($0 - 0.4) < 0.0001 })
    let monoFormat = try #require(AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false
    ))
    let converter = try PCMConverter(inputStreamDescription: monoFormat.streamDescription.pointee)
    let converted = try (0..<10).map { _ in try converter.convert(mono) }
    #expect(abs(converted.reduce(0) { $0 + $1.count } - 16_000) < 512)
    #expect(converted.allSatisfy { $0.allSatisfy(\.isFinite) })
}

@Test func stoppingUnusedMicrophoneDoesNotRequestPermission() async {
    let capture = MicrophoneCapture()
    await capture.stop()
    await capture.suspendForSleep()
    try? await capture.resumeAfterWake()
    await capture.stop()
}
