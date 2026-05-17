import Foundation

/// A single recognized/translated text entry within a session.
struct SessionEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let recognizedText: String
    var translatedText: String

    init(id: UUID = UUID(), recognizedText: String, translatedText: String) {
        self.id = id
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

    private let storageURL: URL

    init() {
        self.storageURL = Self.defaultStorageURL
        loadSessions()
    }

    init(storageURL: URL) {
        self.storageURL = storageURL
        loadSessions()
    }

    private static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = appSupport.appendingPathComponent("OST/Sessions", isDirectory: true)
        return dir.appendingPathComponent("sessions.json")
    }

    func startSession() {
        guard currentSession == nil else { return }
        currentSession = RecordedSession()
        AppLogger.shared.log("Session started", category: .app)
    }

    func record(id: UUID, recognized: String, translated: String) {
        guard var session = currentSession else { return }
        if session.entries.contains(where: { $0.id == id }) { return }
        let entry = SessionEntry(id: id, recognizedText: recognized, translatedText: translated)
        session.entries.append(entry)
        currentSession = session
    }

    func updateTranslation(id: UUID, translated: String) {
        if var session = currentSession,
           let index = session.entries.firstIndex(where: { $0.id == id }) {
            session.entries[index].translatedText = translated
            currentSession = session
            return
        }

        var sessions = pastSessions
        for sessionIndex in sessions.indices {
            if let entryIndex = sessions[sessionIndex].entries.firstIndex(where: { $0.id == id }) {
                sessions[sessionIndex].entries[entryIndex].translatedText = translated
                pastSessions = sessions
                saveSessions()
                return
            }
        }
    }

    func updateCurrentTranslation(id: UUID, translated: String) {
        guard var session = currentSession,
              let index = session.entries.firstIndex(where: { $0.id == id }) else { return }
        session.entries[index].translatedText = translated
        currentSession = session
    }

    func clearCurrentTranslations(ids: [UUID]) {
        guard var session = currentSession else { return }
        let idsToClear = Set(ids)
        var changed = false
        for index in session.entries.indices where idsToClear.contains(session.entries[index].id) {
            session.entries[index].translatedText = ""
            changed = true
        }
        if changed {
            currentSession = session
        }
    }

    func endSession() {
        guard var session = currentSession else { return }
        guard !session.entries.isEmpty else {
            currentSession = nil
            AppLogger.shared.log("Session discarded (0 entries)", category: .app)
            return
        }
        session.endTime = Date()
        pastSessions.insert(session, at: 0)
        pastSessions = Array(pastSessions.prefix(20))
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
        do {
            try ensureStorageDirectory()
            let data = try JSONEncoder().encode(toSave)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            AppLogger.shared.log("Session save failed: \(error.localizedDescription)", category: .error)
        }
    }

    private func loadSessions() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let sessions = try JSONDecoder().decode([RecordedSession].self, from: data)
            pastSessions = Array(sessions.prefix(20))
            if sessions.count > pastSessions.count {
                saveSessions()
            }
        } catch {
            AppLogger.shared.log("Session load failed: \(error.localizedDescription)", category: .error)
        }
    }

    private func ensureStorageDirectory() throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
