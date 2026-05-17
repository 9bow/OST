import AppKit
import SwiftUI

/// Manages the lifecycle of the overlay and settings windows.
/// Class-based so it can be held as a stable reference from the SwiftUI App struct.
@MainActor
final class WindowManager: ObservableObject {

    private var overlayWindow: OverlayWindow?
    private var overlayWindow2: OverlayWindow?  // Translation window for split mode
    private var activeOverlayDisplayMode: String?
    private var settingsWindow: NSWindow?
    private var logWindow: NSWindow?
    private var sessionWindow: NSWindow?

    // MARK: - Overlay

    func showOverlay(appState: AppState, settings: UserSettings) {
        let isSplit = settings.overlayDisplayMode == "split"
        if activeOverlayDisplayMode != nil && activeOverlayDisplayMode != settings.overlayDisplayMode {
            hideOverlay()
        }
        activeOverlayDisplayMode = settings.overlayDisplayMode

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
            let defaultFrame = clampedDefaultFrame(x: 200, y: 200, width: 600, height: 200)
            settings.overlayFrameX = defaultFrame.origin.x
            settings.overlayFrameY = defaultFrame.origin.y
            settings.overlayWidth = defaultFrame.width
            settings.overlayHeight = defaultFrame.height
            settings.overlayLocked = true
            overlayWindow?.setFrame(defaultFrame, display: true, animate: true)
            overlayWindow?.updateLockState(locked: true)
            settings.overlayFrameSaved = false
        }
    }

    func resetOverlay2(settings: UserSettings) {
        let isSplit = settings.overlayDisplayMode == "split"
        if isSplit {
            resetAllOverlaysSideBySide(settings: settings)
        } else {
            let defaultFrame = clampedDefaultFrame(x: 200, y: 450, width: 600, height: 200)
            settings.overlay2FrameX = defaultFrame.origin.x
            settings.overlay2FrameY = defaultFrame.origin.y
            settings.overlay2Width = defaultFrame.width
            settings.overlay2Height = defaultFrame.height
            settings.overlay2Locked = true
            overlayWindow2?.setFrame(defaultFrame, display: true, animate: true)
            overlayWindow2?.updateLockState(locked: true)
            settings.overlay2FrameSaved = false
        }
    }

    /// Resets both overlay windows side-by-side and re-locks them for click-through use.
    private func resetAllOverlaysSideBySide(settings: UserSettings) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap = min(CGFloat(20), screen.width / 20)
        let windowWidth = max(CGFloat(1), min(CGFloat(500), (screen.width - gap) / 2))
        let windowHeight = max(CGFloat(1), min(CGFloat(200), screen.height))

        // Center the pair on visible screen area (accounting for dock/menu bar)
        let totalWidth = windowWidth * 2 + gap
        let startX = screen.origin.x + max(0, (screen.width - totalWidth) / 2)
        let baseY = max(screen.minY, min(screen.minY + 200, screen.maxY - windowHeight))

        let leftFrame = NSRect(x: startX, y: baseY, width: windowWidth, height: windowHeight)
        let rightFrame = NSRect(x: startX + windowWidth + gap, y: baseY, width: windowWidth, height: windowHeight)

        // Recognition window (left)
        settings.overlayFrameX = leftFrame.origin.x
        settings.overlayFrameY = leftFrame.origin.y
        settings.overlayWidth = leftFrame.width
        settings.overlayHeight = leftFrame.height
        overlayWindow?.setFrame(leftFrame, display: true, animate: true)
        settings.overlayLocked = true
        overlayWindow?.updateLockState(locked: true)
        settings.overlayFrameSaved = true

        // Translation window (right)
        settings.overlay2FrameX = rightFrame.origin.x
        settings.overlay2FrameY = rightFrame.origin.y
        settings.overlay2Width = rightFrame.width
        settings.overlay2Height = rightFrame.height
        overlayWindow2?.setFrame(rightFrame, display: true, animate: true)
        settings.overlay2Locked = true
        overlayWindow2?.updateLockState(locked: true)
        settings.overlay2FrameSaved = true
    }

    private func clampedDefaultFrame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frameWidth = max(CGFloat(1), min(width, screen.width))
        let frameHeight = max(CGFloat(1), min(height, screen.height))
        let frameX = max(screen.minX, min(x, screen.maxX - frameWidth))
        let frameY = max(screen.minY, min(y, screen.maxY - frameHeight))
        return NSRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
    }

    func hideOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        activeOverlayDisplayMode = nil
        hideOverlayWindow2()
    }

    private func hideOverlayWindow2() {
        overlayWindow2?.orderOut(nil)
        overlayWindow2 = nil
    }

    // MARK: - Settings

    func showSettings(
        settings: UserSettings,
        onOpenLogs: @escaping () -> Void,
        onOpenSessions: @escaping () -> Void,
        onSubtitleSettingsChanged: @escaping () -> Void,
        onLanguageSettingsChanged: @escaping () -> Void,
        onOnlineFallbackChanged: @escaping () -> Void,
        onSaveSessionHistoryChanged: @escaping () -> Void,
        onSessionWindowAlwaysOnTopChanged: @escaping () -> Void,
        onDisplayModeChanged: @escaping () -> Void
    ) {
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
            onToggleOverlay2Lock: { [weak self] locked in self?.updateOverlay2Lock(locked: locked) },
            onSubtitleSettingsChanged: onSubtitleSettingsChanged,
            onLanguageSettingsChanged: onLanguageSettingsChanged,
            onOnlineFallbackChanged: onOnlineFallbackChanged,
            onSaveSessionHistoryChanged: onSaveSessionHistoryChanged,
            onSessionWindowAlwaysOnTopChanged: onSessionWindowAlwaysOnTopChanged,
            onDisplayModeChanged: onDisplayModeChanged
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
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
        window.isReleasedWhenClosed = false
        window.title = "OST Logs"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        logWindow = window
    }

    // MARK: - Session History

    func updateSessionWindowAlwaysOnTop(_ alwaysOnTop: Bool) {
        sessionWindow?.level = alwaysOnTop ? .floating : .normal
    }

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
        window.isReleasedWhenClosed = false
        window.title = "OST Session History"
        window.level = alwaysOnTop ? .floating : .normal
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        sessionWindow = window
    }
}
