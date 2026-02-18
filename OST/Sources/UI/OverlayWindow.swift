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
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = settings.overlayLocked

        let subtitleView = SubtitleView(
            appState: appState,
            settings: settings,
            translationService: appState.translationService
        )
        contentView = NSHostingView(rootView: subtitleView)

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
        ignoresMouseEvents = locked
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
