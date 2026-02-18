import SwiftUI

struct LogViewerView: View {
    @ObservedObject var logger: AppLogger
    @State private var filterCategory: LogEntry.LogCategory?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logList
        }
        .frame(width: 600, height: 400)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Logs")
                .font(.headline)

            Spacer()

            Picker("Filter", selection: $filterCategory) {
                Text("All").tag(LogEntry.LogCategory?.none)
                Text("App").tag(LogEntry.LogCategory?.some(.app))
                Text("Audio").tag(LogEntry.LogCategory?.some(.audio))
                Text("Speech").tag(LogEntry.LogCategory?.some(.speech))
                Text("Translation").tag(LogEntry.LogCategory?.some(.translation))
                Text("Error").tag(LogEntry.LogCategory?.some(.error))
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 350)

            Button("Clear") {
                logger.clear()
            }
            .accessibilityLabel("Clear logs")
        }
        .padding(8)
    }

    // MARK: - Log List

    private var filteredEntries: [LogEntry] {
        guard let category = filterCategory else { return logger.entries }
        return logger.entries.filter { $0.category == category }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            List(filteredEntries) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.formattedTimestamp)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)

                    Text(entry.category.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(colorForCategory(entry.category))
                        .frame(width: 70, alignment: .leading)

                    Text(entry.message)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .id(entry.id)
            }
            .listStyle(.plain)
            .onChange(of: filteredEntries.count) {
                if let last = filteredEntries.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func colorForCategory(_ category: LogEntry.LogCategory) -> Color {
        switch category {
        case .audio:       return .blue
        case .speech:      return .green
        case .translation: return .orange
        case .app:         return .primary
        case .error:       return .red
        }
    }
}
