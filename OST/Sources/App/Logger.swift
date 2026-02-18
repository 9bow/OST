import Foundation

/// In-app log entry with timestamp and category.
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: LogCategory
    let message: String

    enum LogCategory: String {
        case audio = "Audio"
        case speech = "Speech"
        case translation = "Translation"
        case app = "App"
        case error = "Error"
    }

    var formattedTimestamp: String {
        Self.formatter.string(from: timestamp)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

/// Collects in-app log entries for debugging.
@MainActor
final class AppLogger: ObservableObject {
    static let shared = AppLogger()

    @Published private(set) var entries: [LogEntry] = []

    private let maxEntries = 500

    private init() {}

    func log(_ message: String, category: LogEntry.LogCategory = .app) {
        let entry = LogEntry(timestamp: Date(), category: category, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    /// Thread-safe logging from any context.
    nonisolated static func post(_ message: String, category: LogEntry.LogCategory = .app) {
        Task { @MainActor in
            shared.log(message, category: category)
        }
    }

    func clear() {
        entries.removeAll()
    }
}
