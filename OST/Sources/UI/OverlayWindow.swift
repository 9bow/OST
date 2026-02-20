import AppKit
import SwiftUI

/// Identifies which overlay role this window serves, determining frame persistence keys.
enum OverlayRole {
    case combined      // Single window: uses primary frame keys
    case recognition   // Split mode recognition: uses primary frame keys
    case translation   // Split mode translation: uses overlay2 frame keys
}

final class OverlayWindow: NSPanel {

    private let settings: UserSettings
    let role: OverlayRole

    init(contentView: AnyView, settings: UserSettings, role: OverlayRole = .combined) {
        self.settings = settings
        self.role = role

        var initialFrame: NSRect
        switch role {
        case .combined, .recognition:
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
        case .translation:
            if settings.overlay2FrameSaved {
                initialFrame = NSRect(
                    x: settings.overlay2FrameX,
                    y: settings.overlay2FrameY,
                    width: settings.overlay2Width,
                    height: settings.overlay2Height
                )
            } else {
                initialFrame = NSRect(x: 200, y: 450, width: settings.overlay2Width, height: settings.overlay2Height)
            }
        }

        // Ensure frame is within visible screen area
        initialFrame = Self.clampToScreen(initialFrame)

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
        let locked = isLocked
        ignoresMouseEvents = locked
        isMovableByWindowBackground = !locked

        let container = NSView(frame: NSRect(origin: .zero, size: initialFrame.size))
        container.autoresizesSubviews = true

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.sizingOptions = []
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        self.contentView = container

        NotificationCenter.default.addObserver(
            self, selector: #selector(persistFrame),
            name: NSWindow.didMoveNotification, object: self
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(persistFrame),
            name: NSWindow.didResizeNotification, object: self
        )
    }

    private var isLocked: Bool {
        switch role {
        case .combined, .recognition: return settings.overlayLocked
        case .translation: return settings.overlay2Locked
        }
    }

    @objc private func persistFrame() {
        let f = frame
        switch role {
        case .combined, .recognition:
            settings.overlayFrameX = f.origin.x
            settings.overlayFrameY = f.origin.y
            settings.overlayWidth = f.size.width
            settings.overlayHeight = f.size.height
            settings.overlayFrameSaved = true
        case .translation:
            settings.overlay2FrameX = f.origin.x
            settings.overlay2FrameY = f.origin.y
            settings.overlay2Width = f.size.width
            settings.overlay2Height = f.size.height
            settings.overlay2FrameSaved = true
        }
    }

    func updateLockState(locked: Bool) {
        ignoresMouseEvents = locked
        isMovableByWindowBackground = !locked
    }

    func resetFrame() {
        let defaultFrame: NSRect
        switch role {
        case .combined, .recognition:
            defaultFrame = NSRect(x: 200, y: 200, width: 600, height: 200)
        case .translation:
            defaultFrame = NSRect(x: 200, y: 450, width: 600, height: 200)
        }
        setFrame(defaultFrame, display: true, animate: true)
    }

    /// Ensures the frame is at least partially visible on screen.
    private static func clampToScreen(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.main?.visibleFrame else { return frame }
        var f = frame
        // Ensure minimum size
        f.size.width = max(f.size.width, 200)
        f.size.height = max(f.size.height, 100)
        // Clamp position so at least 100px is visible on screen
        let minVisible: CGFloat = 100
        f.origin.x = max(screen.minX - f.width + minVisible, min(f.origin.x, screen.maxX - minVisible))
        f.origin.y = max(screen.minY, min(f.origin.y, screen.maxY - 40))
        return f
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}
