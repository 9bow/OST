import Foundation

/// A single recognized/translated text entry within a session.
struct SessionEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let recognizedText: String
    let translatedText: String

    init(recognizedText: String, translatedText: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.recognizedText = recognizedText
        self.translatedText = translatedText
    }

    var formattedTimestamp: String {
        Self.formatter.string(from: timestamp)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

/// A recorded capture session.
struct RecordedSession: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var entries: [SessionEntry]

    init() {
        self.id = UUID()
        self.startTime = Date()
        self.entries = []
    }

    var formattedDate: String {
        Self.formatter.string(from: startTime)
    }

    var duration: String {
        let end = endTime ?? Date()
        let interval = end.timeIntervalSince(startTime)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

/// Records recognition/translation results per session and persists to disk.
@MainActor
final class SessionRecorder: ObservableObject {
    @Published private(set) var currentSession: RecordedSession?
    @Published private(set) var pastSessions: [RecordedSession] = []

    private let storageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("OST/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }()

    init() {
        loadSessions()
    }

    func startSession() {
        currentSession = RecordedSession()
        AppLogger.shared.log("Session started", category: .app)
    }

    func record(recognized: String, translated: String) {
        guard currentSession != nil else { return }
        let entry = SessionEntry(recognizedText: recognized, translatedText: translated)
        currentSession?.entries.append(entry)
    }

    func endSession() {
        guard var session = currentSession else { return }
        session.endTime = Date()
        pastSessions.insert(session, at: 0)
        currentSession = nil
        saveSessions()
        AppLogger.shared.log("Session ended (\(session.entries.count) entries)", category: .app)
    }

    func clearHistory() {
        pastSessions.removeAll()
        saveSessions()
    }

    // MARK: - Persistence

    private func saveSessions() {
        // Keep last 20 sessions
        let toSave = Array(pastSessions.prefix(20))
        guard let data = try? JSONEncoder().encode(toSave) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func loadSessions() {
        guard let data = try? Data(contentsOf: storageURL),
              let sessions = try? JSONDecoder().decode([RecordedSession].self, from: data) else { return }
        pastSessions = sessions
    }
}
