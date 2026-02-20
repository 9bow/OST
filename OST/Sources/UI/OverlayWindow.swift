import AppKit
import SwiftUI

final class OverlayWindow: NSPanel {

    private let settings: UserSettings

    init(appState: AppState, settings: UserSettings) {
        self.settings = settings
        let initialFrame: NSRect
        if settings.overlayFrameSaved {
            initialFrame = NSRect(
                x: settings.overlayFrameX,
                y: settings.overlayFrameY,
                width: settings.overlayWidth,
                height: settings.overlayHeight
            )
        } else {
            initialFrame = NSRect(x: 200, y: 200, width: settings.overlayWidth, height: settings.overlayHeight)
        }
        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Apply initial lock state
        let locked = settings.overlayLocked
        ignoresMouseEvents = locked
        isMovableByWindowBackground = !locked

        let subtitleView = SubtitleView(
            appState: appState,
            settings: settings,
            translationService: appState.translationService
        )
        let hostingView = NSHostingView(rootView: subtitleView)
        hostingView.sizingOptions = []

        // Wrap in a plain NSView container to completely prevent
        // NSHostingView from driving window size changes
        let container = NSView()
        container.autoresizesSubviews = true
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        contentView = container

        NotificationCenter.default.addObserver(
            self, selector: #selector(persistFrame),
            name: NSWindow.didMoveNotification, object: self
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(persistFrame),
            name: NSWindow.didResizeNotification, object: self
        )
    }

    @objc private func persistFrame() {
        let f = frame
        settings.overlayFrameX = f.origin.x
        settings.overlayFrameY = f.origin.y
        settings.overlayWidth = f.size.width
        settings.overlayHeight = f.size.height
        settings.overlayFrameSaved = true
    }

    func updateLockState(locked: Bool) {
        if locked {
            ignoresMouseEvents = true
            isMovableByWindowBackground = false
        } else {
            ignoresMouseEvents = false
            isMovableByWindowBackground = true
        }
    }

    func resetFrame() {
        let defaultFrame = NSRect(x: 200, y: 200, width: 600, height: 200)
        setFrame(defaultFrame, display: true, animate: true)
        // Note: persistFrame() will be called via didResizeNotification.
        // WindowManager.resetOverlay() sets overlayFrameSaved = false AFTER this call.
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}
