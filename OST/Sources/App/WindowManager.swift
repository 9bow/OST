import AppKit
import SwiftUI

/// Manages the lifecycle of the overlay and settings windows.
/// Class-based so it can be held as a stable reference from the SwiftUI App struct.
@MainActor
final class WindowManager: ObservableObject {

    private var overlayWindow: OverlayWindow?
    private var settingsWindow: NSWindow?
    private var logWindow: NSWindow?
    private var sessionWindow: NSWindow?

    // MARK: - Overlay

    func showOverlay(appState: AppState, settings: UserSettings) {
        if let existing = overlayWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = OverlayWindow(appState: appState, settings: settings)
        window.makeKeyAndOrderFront(nil)
        overlayWindow = window
    }

    func updateOverlayLock(locked: Bool) {
        overlayWindow?.updateLockState(locked: locked)
    }

    func hideOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    // MARK: - Settings

    func showSettings(settings: UserSettings, onOpenLogs: @escaping () -> Void, onOpenSessions: @escaping () -> Void) {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(settings: settings, onOpenLogs: onOpenLogs, onOpenSessions: onOpenSessions)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OST Settings"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Log Viewer

    func showLogViewer() {
        if let existing = logWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = LogViewerView(logger: AppLogger.shared)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OST Logs"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        logWindow = window
    }

    // MARK: - Session History

    func showSessionHistory(recorder: SessionRecorder, alwaysOnTop: Bool) {
        if let existing = sessionWindow, existing.isVisible {
            existing.level = alwaysOnTop ? .floating : .normal
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SessionHistoryView(recorder: recorder)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OST Session History"
        window.level = alwaysOnTop ? .floating : .normal
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        sessionWindow = window
    }
}
