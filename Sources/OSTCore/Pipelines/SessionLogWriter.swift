import Foundation

public struct SessionLogURLs: Sendable, Equatable {
    public let transcript: URL
    public let translation: URL

    public init(transcript: URL, translation: URL) {
        self.transcript = transcript
        self.translation = translation
    }
}

public actor SessionLogWriter {
    private var urls: SessionLogURLs?
    private var orderedIDs: [UUID] = []
    private var transcripts: [UUID: String] = [:]
    private var translations: [UUID: String] = [:]
    private var audioSources: [UUID: AudioSource] = [:]

    public init() {}

    @discardableResult
    public func start(directory: URL, startedAt: Date = Date()) throws -> SessionLogURLs {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let prefix = formatter.string(from: startedAt)
        let urls = SessionLogURLs(
            transcript: directory.appending(path: "\(prefix)-transcript.txt"),
            translation: directory.appending(path: "\(prefix)-translation.txt")
        )
        self.urls = urls
        orderedIDs.removeAll(keepingCapacity: true)
        transcripts.removeAll(keepingCapacity: true)
        translations.removeAll(keepingCapacity: true)
        audioSources.removeAll(keepingCapacity: true)
        try Data().write(to: urls.transcript, options: .atomic)
        try Data().write(to: urls.translation, options: .atomic)
        return urls
    }

    public func recordTranscript(id: UUID, text: String, audioSource: AudioSource = .systemAudio) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let urls else { return }
        register(id)
        transcripts[id] = text
        audioSources[id] = audioSource
        try render(transcripts, to: urls.transcript)
    }

    public func recordTranslation(id: UUID, text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let urls else { return }
        register(id)
        translations[id] = text
        try render(translations, to: urls.translation)
    }

    public func finish() {
        urls = nil
        orderedIDs.removeAll()
        transcripts.removeAll()
        translations.removeAll()
        audioSources.removeAll()
    }

    private func register(_ id: UUID) {
        if !orderedIDs.contains(id) { orderedIDs.append(id) }
    }

    private func render(_ records: [UUID: String], to url: URL) throws {
        let text = orderedIDs.compactMap { id -> String? in
            guard let text = records[id] else { return nil }
            return audioSources[id] == .microphone ? "[Microphone] " + text : text
        }.joined(separator: "\n")
        let contents = text.isEmpty ? "" : text + "\n"
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
