import SwiftUI
import AppKit

struct SessionHistoryView: View {
    @ObservedObject var recorder: SessionRecorder
    @State private var selectedSession: RecordedSession?
    @State private var showClearHistoryConfirmation = false

    var body: some View {
        HSplitView {
            sessionList
                .frame(minWidth: 200, maxWidth: 250)
            sessionDetail
                .frame(minWidth: 350)
        }
        .frame(width: 650, height: 450)
        .alert("Clear Session History?", isPresented: $showClearHistoryConfirmation) {
            Button("Clear All", role: .destructive) {
                recorder.clearHistory()
                selectedSession = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all saved sessions.")
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sessions")
                    .font(.headline)
                Spacer()
                Button("Clear All") {
                    showClearHistoryConfirmation = true
                }
                .font(.caption)
                .disabled(recorder.pastSessions.isEmpty)
                .accessibilityLabel("Clear session history")
            }
            .padding(8)

            Divider()

            if let current = recorder.currentSession {
                Button {
                    selectedSession = current
                } label: {
                    HStack {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        VStack(alignment: .leading) {
                            Text("Active Session")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("\(current.entries.count) entries")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                Divider()
            }

            List(recorder.pastSessions, selection: $selectedSession) { session in
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.formattedDate)
                        .font(.caption)
                    HStack {
                        Text("\(session.entries.count) entries")
                        Text("(\(session.duration))")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                .tag(session)
                .accessibilityLabel("Session from \(session.formattedDate)")
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Session Detail

    private var sessionDetail: some View {
        VStack(spacing: 0) {
            if let session = displayedSession {
                HStack {
                    Text(session.formattedDate)
                        .font(.headline)
                    Spacer()
                    Text("\(session.entries.count) entries - \(session.duration)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Export…") {
                        exportSession(session)
                    }
                    .font(.caption)
                    .disabled(session.entries.isEmpty)
                }
                .padding(8)

                Divider()

                List(session.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.formattedTimestamp)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        if !entry.recognizedText.isEmpty {
                            Text(entry.recognizedText)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        if !entry.translatedText.isEmpty {
                            Text(entry.translatedText)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .listStyle(.plain)
            } else {
                Text("Select a session to view details")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var displayedSession: RecordedSession? {
        guard let selectedSession else { return nil }
        if let current = recorder.currentSession, current.id == selectedSession.id {
            return current
        }
        return recorder.pastSessions.first { $0.id == selectedSession.id }
    }

    // MARK: - Export

    private func exportSession(_ session: RecordedSession) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "OST-\(session.formattedDate.replacingOccurrences(of: ":", with: "-")).txt"

        // Temporarily lower the session window level so the save panel appears in front
        // when "Always on top" (.floating) is active.
        let hostWindow = NSApp.keyWindow
        let originalLevel = hostWindow?.level
        hostWindow?.level = .normal

        panel.begin { response in
            hostWindow?.level = originalLevel ?? .normal
            guard response == .OK, let url = panel.url else { return }
            let sessionToExport = latestSession(id: session.id) ?? session
            let text = sessionText(sessionToExport)
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                AppLogger.shared.log("Session export failed: \(error.localizedDescription)", category: .error)
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func latestSession(id: UUID) -> RecordedSession? {
        if let current = recorder.currentSession, current.id == id {
            return current
        }
        return recorder.pastSessions.first { $0.id == id }
    }

    private func sessionText(_ session: RecordedSession) -> String {
        var lines: [String] = []
        lines.append("OST Session: \(session.formattedDate)  [\(session.duration)]")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")
        for entry in session.entries {
            lines.append("[\(entry.formattedTimestamp)]")
            if !entry.recognizedText.isEmpty { lines.append(entry.recognizedText) }
            if !entry.translatedText.isEmpty { lines.append("→ \(entry.translatedText)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Hashable Conformance for List Selection

extension RecordedSession: Hashable {
    static func == (lhs: RecordedSession, rhs: RecordedSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
