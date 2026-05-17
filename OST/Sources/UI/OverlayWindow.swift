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
        minSize = NSSize(width: min(200, initialFrame.width), height: min(100, initialFrame.height))

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

    /// Ensures the frame is at least partially visible on screen.
    private static func clampToScreen(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.main?.visibleFrame else { return frame }
        var f = frame
        f.origin.x = finite(f.origin.x, fallback: screen.midX - 300)
        f.origin.y = finite(f.origin.y, fallback: screen.minY + 200)
        f.size.width = finite(f.size.width, fallback: 600)
        f.size.height = finite(f.size.height, fallback: 200)
        // Keep restored windows fully visible, even after display changes.
        let minWidth = min(200, screen.width)
        let minHeight = min(100, screen.height)
        f.size.width = min(max(f.size.width, minWidth), screen.width)
        f.size.height = min(max(f.size.height, minHeight), screen.height)
        f.origin.x = max(screen.minX, min(f.origin.x, screen.maxX - f.width))
        f.origin.y = max(screen.minY, min(f.origin.y, screen.maxY - f.height))
        return f
    }

    private static func finite(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite ? value : fallback
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}
