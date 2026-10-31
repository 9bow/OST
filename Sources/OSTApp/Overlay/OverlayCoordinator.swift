import AppKit
import OSTCore
import SwiftUI
import Translation

private final class OverlayObserverBag: @unchecked Sendable {
    private var observers: [NSObjectProtocol] = []

    func append(_ observer: NSObjectProtocol) {
        observers.append(observer)
    }

    func invalidate() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    deinit {
        invalidate()
    }
}

@MainActor
final class OverlayCoordinator {
    private struct SizingSignature: Codable, Equatable {
        let lineCount: Int
        let sourceFontSize: Double
        let translationFontSize: Double
        let previewFontSize: Double
        // Legacy sizing signatures omit this value when both tracks are visible.
        let subtitleDisplayMode: SubtitleDisplayMode?
        let microphoneMode: MicrophoneMode?
    }

    private let state: OverlayState
    private let preferences: PreferencesStore
    private let translationPackCoordinator: TranslationPackCoordinator
    private var panels: [OverlayPanelKind: SubtitlePanel] = [:]
    private let observerBag = OverlayObserverBag()
    private var sizingSignature: SizingSignature
    private var appliedSizingSignatures: [OverlayPanelKind: SizingSignature] = [:]
    private(set) var isVisible = true

    init(
        state: OverlayState,
        preferences: PreferencesStore,
        translationPackCoordinator: TranslationPackCoordinator
    ) {
        self.state = state
        self.preferences = preferences
        self.translationPackCoordinator = translationPackCoordinator
        sizingSignature = SizingSignature(
            lineCount: preferences.overlayLineCount,
            sourceFontSize: preferences.sourceFontSize,
            translationFontSize: preferences.translationFontSize,
            previewFontSize: preferences.previewFontSize,
            subtitleDisplayMode: preferences.subtitleDisplayMode == .both ? nil : preferences.subtitleDisplayMode,
            microphoneMode: preferences.microphoneMode == .off ? nil : preferences.microphoneMode
        )
        for kind in [OverlayPanelKind.combined, .source, .translation] {
            if let data = UserDefaults.standard.data(forKey: sizingDefaultsKey(for: kind)),
               let signature = try? JSONDecoder().decode(SizingSignature.self, from: data) {
                appliedSizingSignatures[kind] = signature
            }
        }
        observerBag.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restorePanelsToVisibleScreens() }
        })
    }

    deinit {
        observerBag.invalidate()
    }

    func show() {
        isVisible = true
        applyPreferences()
    }

    func hide() {
        isVisible = false
        panels.values.forEach { $0.orderOut(nil) }
    }

    func toggleVisibility() {
        isVisible ? hide() : show()
    }

    func applyPreferences() {
        guard isVisible else { return }
        let newSizingSignature = SizingSignature(
            lineCount: preferences.overlayLineCount,
            sourceFontSize: preferences.sourceFontSize,
            translationFontSize: preferences.translationFontSize,
            previewFontSize: preferences.previewFontSize,
            subtitleDisplayMode: preferences.subtitleDisplayMode == .both ? nil : preferences.subtitleDisplayMode,
            microphoneMode: (state.microphoneMode ?? preferences.microphoneMode) == .off
                ? nil : (state.microphoneMode ?? preferences.microphoneMode)
        )
        sizingSignature = newSizingSignature
        switch preferences.overlayLayout {
        case .combined:
            panel(for: .source).orderOut(nil)
            panel(for: .translation).orderOut(nil)
            configure(
                panel(for: .combined),
                kind: .combined,
                name: "OSTCombinedOverlay"
            )
            panel(for: .combined).orderFrontRegardless()
        case .split:
            panel(for: .combined).orderOut(nil)
            if preferences.subtitleDisplayMode.showsSource {
                configure(
                    panel(for: .source),
                    kind: .source,
                    name: "OSTSourceOverlay"
                )
                panel(for: .source).orderFrontRegardless()
            } else {
                panels[.source]?.orderOut(nil)
            }
            if preferences.subtitleDisplayMode.showsTranslation {
                configure(
                    panel(for: .translation),
                    kind: .translation,
                    name: "OSTTranslationOverlay"
                )
                panel(for: .translation).orderFrontRegardless()
            } else {
                panels[.translation]?.orderOut(nil)
            }
        }
    }

    func resetFrames() {
        for name in ["OSTCombinedOverlay", "OSTSourceOverlay", "OSTTranslationOverlay"] {
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)")
        }
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        applyPreferences()
    }

    private func panel(for kind: OverlayPanelKind) -> SubtitlePanel {
        if let panel = panels[kind] { return panel }
        var style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        if !preferences.overlayLocked { style.insert(.resizable) }
        let panel = SubtitlePanel(
            contentRect: defaultFrame(for: kind),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        panel.title = title(for: kind)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.minSize = minimumSize(for: kind)
        panel.contentView = NSHostingView(rootView: TranslationTaskOverlayRoot(
            kind: kind,
            state: state,
            preferences: preferences,
            translationPackCoordinator: translationPackCoordinator
        ))
        panels[kind] = panel
        return panel
    }

    private func configure(
        _ panel: SubtitlePanel,
        kind: OverlayPanelKind,
        name: String
    ) {
        let resizeToPreferred = appliedSizingSignatures[kind] != sizingSignature
        let minimumSize = minimumSize(for: kind)
        panel.minSize = minimumSize
        panel.ignoresMouseEvents = preferences.overlayLocked
        panel.isMovableByWindowBackground = !preferences.overlayLocked
        if preferences.overlayLocked {
            panel.styleMask.remove(.resizable)
        } else {
            panel.styleMask.insert(.resizable)
        }
        if panel.frameAutosaveName != name {
            panel.setFrameAutosaveName(name)
            _ = panel.setFrameUsingName(name)
        }
        if resizeToPreferred
            || panel.frame.width < minimumSize.width
            || panel.frame.height < minimumSize.height {
            var frame = panel.frame
            frame.size.width = max(frame.width, minimumSize.width)
            frame.size.height = resizeToPreferred
                ? minimumSize.height
                : max(frame.height, minimumSize.height)
            panel.setFrame(frame, display: true)
        }
        clamp(panel)
        appliedSizingSignatures[kind] = sizingSignature
        if let data = try? JSONEncoder().encode(sizingSignature) {
            UserDefaults.standard.set(data, forKey: sizingDefaultsKey(for: kind))
        }
    }

    private func restorePanelsToVisibleScreens() {
        panels.values.forEach(clamp)
    }

    private func clamp(_ panel: NSPanel) {
        guard let primary = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame else { return }
        let frame = OverlayFrameRestorer.restoredFrame(
            stored: panel.frame,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            primaryVisibleFrame: primary,
            defaultSize: panel.frame.size
        )
        panel.setFrame(frame, display: true)
    }

    private func defaultFrame(for kind: OverlayPanelKind) -> NSRect {
        guard let visible = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame else {
            return NSRect(x: 100, y: 100, width: 720, height: 180)
        }
        switch kind {
        case .combined:
            return OverlayFrameRestorer.restoredFrame(
                stored: nil,
                visibleFrames: [visible],
                primaryVisibleFrame: visible,
                defaultSize: preferredSize(for: .combined)
            )
        case .translation:
            let size = preferredSize(for: .translation)
            return NSRect(x: visible.midX - 360, y: visible.minY + 48, width: size.width, height: size.height)
        case .source:
            let sourceSize = preferredSize(for: .source)
            let translationHeight = preferredSize(for: .translation).height
            return NSRect(
                x: visible.midX - 360,
                y: visible.minY + 60 + translationHeight,
                width: sourceSize.width,
                height: sourceSize.height
            )
        }
    }

    private func preferredSize(for kind: OverlayPanelKind) -> NSSize {
        let maximumHeight = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? 900
        switch kind {
        case .combined:
            return OverlaySizing.combinedSize(
                lineCount: preferences.overlayLineCount,
                sourceFontSize: preferences.sourceFontSize,
                translationFontSize: preferences.translationFontSize,
                previewFontSize: preferences.previewFontSize,
                displayMode: preferences.subtitleDisplayMode,
                microphoneMode: state.microphoneMode ?? preferences.microphoneMode,
                maximumHeight: maximumHeight
            )
        case .source:
            return OverlaySizing.sourceSize(
                lineCount: preferences.overlayLineCount,
                fontSize: preferences.sourceFontSize,
                microphoneMode: state.microphoneMode ?? preferences.microphoneMode,
                maximumHeight: maximumHeight
            )
        case .translation:
            return OverlaySizing.translationSize(
                lineCount: preferences.overlayLineCount,
                fontSize: preferences.translationFontSize,
                previewFontSize: preferences.previewFontSize,
                microphoneMode: state.microphoneMode ?? preferences.microphoneMode,
                maximumHeight: maximumHeight
            )
        }
    }

    private func minimumSize(for kind: OverlayPanelKind) -> NSSize {
        let preferred = preferredSize(for: kind)
        return NSSize(width: 320, height: preferred.height)
    }

    private func title(for kind: OverlayPanelKind) -> String {
        switch kind {
        case .combined: "OST Subtitles"
        case .source: "OST Transcript"
        case .translation: "OST Translation"
        }
    }

    private func sizingDefaultsKey(for kind: OverlayPanelKind) -> String {
        switch kind {
        case .combined: "OSTCombinedOverlay.sizing.v3"
        case .source: "OSTSourceOverlay.sizing.v3"
        case .translation: "OSTTranslationOverlay.sizing.v3"
        }
    }
}

private struct TranslationTaskOverlayRoot: View {
    let kind: OverlayPanelKind
    @ObservedObject var state: OverlayState
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var translationPackCoordinator: TranslationPackCoordinator

    var body: some View {
        OverlayContentView(
            kind: kind,
            state: state,
            preferences: preferences
        )
        .translationTask(hostedConfiguration) { session in
            await translationPackCoordinator.prepare(using: session)
        }
    }

    private var hostedConfiguration: TranslationSession.Configuration? {
        switch (preferences.overlayLayout, kind) {
        case (.combined, .combined):
            translationPackCoordinator.configuration
        case (.split, .source) where preferences.subtitleDisplayMode.showsSource:
            translationPackCoordinator.configuration
        case (.split, .translation) where !preferences.subtitleDisplayMode.showsSource:
            translationPackCoordinator.configuration
        default:
            nil
        }
    }
}
