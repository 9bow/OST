import Foundation
import OSTCore
import Testing

@Test func microphonePreferencesMigrateAndRoundTrip() throws {
    let legacy = try JSONDecoder().decode(PreferencesSnapshot.self, from: Data("{}".utf8))
    #expect(legacy.microphoneMode == .off)
    #expect(legacy.microphoneColor != legacy.sourceColor)
    #expect(legacy.microphoneColor != legacy.translationColor)
    for mode in MicrophoneMode.allCases {
        let original = PreferencesSnapshot(
            microphoneMode: mode,
            microphoneColor: RGBAColor(red: 0.2, green: 0.8, blue: 0.5, alpha: 0.7)
        )
        let restored = try JSONDecoder().decode(
            PreferencesSnapshot.self,
            from: JSONEncoder().encode(original)
        )
        #expect(restored == original)
        #expect(mode.translates(.systemAudio))
        #expect(mode.translates(.microphone) == (mode == .transcriptionAndTranslation))
        #expect(mode.isEnabled == (mode != .off))
    }
}

@Test func simultaneousPreviewsKeepTheirOwnTranslationsAndFinals() async throws {
    let store = SegmentStore()
    var system = TranscriptSegment(
        startTime: .zero, language: .english, sourceText: "Hello", isFinal: false
    )
    var microphone = TranscriptSegment(
        startTime: .zero, language: .english, sourceText: "Hello", isFinal: false,
        audioSource: .microphone
    )
    _ = await store.merge(.segment(system), limit: 4)
    let previews = await store.merge(.segment(microphone), limit: 4)
    #expect(previews.count == 2)
    _ = await store.applyTranslation(segmentID: system.id, text: "시스템", limit: 4)
    let translated = await store.applyTranslation(segmentID: microphone.id, text: "마이크", limit: 4)
    #expect(translated.first { $0.id == system.id }?.translatedText == "시스템")
    #expect(translated.first { $0.id == microphone.id }?.translatedText == "마이크")

    system.isFinal = true
    let partlyFinal = await store.merge(.segment(system), limit: 4)
    #expect(partlyFinal.count == 2)
    #expect(partlyFinal.first { $0.id == microphone.id }?.isFinal == false)
    microphone.isFinal = true
    let finals = await store.merge(.segment(microphone), limit: 4)
    #expect(finals.count == 2)
    #expect(finals.allSatisfy { $0.isFinal })
    #expect(finals.first { $0.id == system.id }?.translatedText == "시스템")
    #expect(finals.first { $0.id == microphone.id }?.translatedText == "마이크")
    #expect(DisplaySegmentGrouper.group(finals).count == 2)
    #expect(await store.visibleSegments(limit: 1).count == 1)
    await store.clear()
    #expect(await store.visibleSegments().isEmpty)
}

@Test func olderMicrophonePreviewDoesNotReplaceSystemPreview() async {
    let store = SegmentStore()
    let system = TranscriptSegment(
        startTime: .seconds(10), language: .english, sourceText: "System", isFinal: false
    )
    let microphone = TranscriptSegment(
        startTime: .seconds(1), language: .english, sourceText: "Microphone", isFinal: false,
        audioSource: .microphone
    )
    _ = await store.merge(.segment(system))
    let visible = await store.merge(.segment(microphone))
    #expect(Set(visible.map(\.id)) == [system.id, microphone.id])
}

@Test func microphoneSizingReservesIndependentPreviews() {
    let off = OverlaySizing.combinedSize(
        lineCount: 3, sourceFontSize: 20, translationFontSize: 28, maximumHeight: 2_000
    )
    let transcription = OverlaySizing.combinedSize(
        lineCount: 3, sourceFontSize: 20, translationFontSize: 28,
        microphoneMode: .transcription, maximumHeight: 2_000
    )
    let translated = OverlaySizing.combinedSize(
        lineCount: 3, sourceFontSize: 20, translationFontSize: 28,
        microphoneMode: .transcriptionAndTranslation, maximumHeight: 2_000
    )
    #expect(transcription.height - off.height == 50)
    #expect(translated.height - transcription.height == 70)
    #expect(OverlaySizing.translationSize(
        lineCount: 3, fontSize: 28, microphoneMode: .transcription, maximumHeight: 2_000
    ) == OverlaySizing.translationSize(lineCount: 3, fontSize: 28, maximumHeight: 2_000))
}

@Test func savedMicrophoneTranscriptsAndTranslationsKeepSourceLabels() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "ost-microphone-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = SessionLogWriter()
    let urls = try await writer.start(directory: directory)
    let systemID = UUID()
    let microphoneID = UUID()
    try await writer.recordTranscript(id: systemID, text: "System speech")
    try await writer.recordTranscript(id: microphoneID, text: "My speech", audioSource: .microphone)
    try await writer.recordTranslation(id: systemID, text: "시스템 음성")
    try await writer.recordTranslation(id: microphoneID, text: "내 음성")
    #expect(try String(contentsOf: urls.transcript, encoding: .utf8) == "System speech\n[Microphone] My speech\n")
    #expect(try String(contentsOf: urls.translation, encoding: .utf8) == "시스템 음성\n[Microphone] 내 음성\n")
    await writer.finish()
}
