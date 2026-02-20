import AppKit
import SwiftUI

/// Manages the lifecycle of the overlay and settings windows.
/// Class-based so it can be held as a stable reference from the SwiftUI App struct.
@MainActor
final class WindowManager: ObservableObject {

    private var overlayWindow: OverlayWindow?
    private var overlayWindow2: OverlayWindow?  // Translation window for split mode
    private var settingsWindow: NSWindow?
    private var logWindow: NSWindow?
    private var sessionWindow: NSWindow?

    // MARK: - Overlay

    func showOverlay(appState: AppState, settings: UserSettings) {
        let isSplit = settings.overlayDisplayMode == "split"

        if isSplit {
            showSplitOverlay(appState: appState, settings: settings)
        } else {
            showCombinedOverlay(appState: appState, settings: settings)
        }
    }

    private func showCombinedOverlay(appState: AppState, settings: UserSettings) {
        // Hide any split windows
        hideOverlayWindow2()

        if let existing = overlayWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let view = AnyView(SubtitleView(
            appState: appState,
            settings: settings,
            translationService: appState.translationService
        ))
        let window = OverlayWindow(contentView: view, settings: settings, role: .combined)
        window.makeKeyAndOrderFront(nil)
        overlayWindow = window
    }

    private func showSplitOverlay(appState: AppState, settings: UserSettings) {
        // Recognition window (primary)
        if let existing = overlayWindow {
            existing.makeKeyAndOrderFront(nil)
        } else {
            let recognitionView = AnyView(RecognitionOverlayView(
                appState: appState,
                settings: settings
            ))
            let window = OverlayWindow(contentView: recognitionView, settings: settings, role: .recognition)
            window.makeKeyAndOrderFront(nil)
            overlayWindow = window
        }

        // Translation window (secondary)
        if let existing = overlayWindow2 {
            existing.makeKeyAndOrderFront(nil)
        } else {
            let translationView = AnyView(TranslationOverlayView(
                appState: appState,
                settings: settings,
                translationService: appState.translationService
            ))
            let window = OverlayWindow(contentView: translationView, settings: settings, role: .translation)
            window.makeKeyAndOrderFront(nil)
            overlayWindow2 = window
        }
    }

    func updateOverlayLock(locked: Bool) {
        overlayWindow?.updateLockState(locked: locked)
    }

    func updateOverlay2Lock(locked: Bool) {
        overlayWindow2?.updateLockState(locked: locked)
    }

    func resetOverlay(settings: UserSettings) {
        let isSplit = settings.overlayDisplayMode == "split"
        if isSplit {
            resetAllOverlaysSideBySide(settings: settings)
        } else {
            settings.overlayLocked = false
            overlayWindow?.resetFrame()
            overlayWindow?.updateLockState(locked: false)
            settings.overlayFrameSaved = false
        }
    }

    func resetOverlay2(settings: UserSettings) {
        let isSplit = settings.overlayDisplayMode == "split"
        if isSplit {
            resetAllOverlaysSideBySide(settings: settings)
        } else {
            settings.overlay2Locked = false
            overlayWindow2?.resetFrame()
            overlayWindow2?.updateLockState(locked: false)
            settings.overlay2FrameSaved = false
        }
    }

    /// Resets both overlay windows side-by-side and unlocks them.
    private func resetAllOverlaysSideBySide(settings: UserSettings) {
        let windowWidth: CGFloat = 500
        let windowHeight: CGFloat = 200
        let gap: CGFloat = 20

        // Center the pair on visible screen area (accounting for dock/menu bar)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let totalWidth = windowWidth * 2 + gap
        let startX = screen.origin.x + max(0, (screen.width - totalWidth) / 2)
        let baseY = screen.origin.y + 200

        let leftFrame = NSRect(x: startX, y: baseY, width: windowWidth, height: windowHeight)
        let rightFrame = NSRect(x: startX + windowWidth + gap, y: baseY, width: windowWidth, height: windowHeight)

        // Recognition window (left)
        overlayWindow?.setFrame(leftFrame, display: true, animate: true)
        settings.overlayLocked = false
        overlayWindow?.updateLockState(locked: false)
        settings.overlayFrameSaved = false

        // Translation window (right)
        overlayWindow2?.setFrame(rightFrame, display: true, animate: true)
        settings.overlay2Locked = false
        overlayWindow2?.updateLockState(locked: false)
        settings.overlay2FrameSaved = false
    }

    func hideOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        hideOverlayWindow2()
    }

    private func hideOverlayWindow2() {
        overlayWindow2?.orderOut(nil)
        overlayWindow2 = nil
    }

    // MARK: - Settings

    func showSettings(settings: UserSettings, onOpenLogs: @escaping () -> Void, onOpenSessions: @escaping () -> Void) {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(
            settings: settings,
            onOpenLogs: onOpenLogs,
            onOpenSessions: onOpenSessions,
            onResetOverlay: { [weak self] in self?.resetOverlay(settings: settings) },
            onResetOverlay2: { [weak self] in self?.resetOverlay2(settings: settings) },
            onToggleOverlayLock: { [weak self] locked in self?.updateOverlayLock(locked: locked) },
            onToggleOverlay2Lock: { [weak self] locked in self?.updateOverlay2Lock(locked: locked) }
        )
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
