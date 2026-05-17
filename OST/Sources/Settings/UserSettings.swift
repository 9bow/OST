import SwiftUI

private let defaultWhiteColorData: Data = {
    guard let data = try? NSKeyedArchiver.archivedData(
        withRootObject: NSColor.white,
        requiringSecureCoding: true
    ) else { return Data() }
    return data
}()

private let defaultBlackColorData: Data = {
    guard let data = try? NSKeyedArchiver.archivedData(
        withRootObject: NSColor.black,
        requiringSecureCoding: true
    ) else { return Data() }
    return data
}()

private let defaultCyanColorData: Data = {
    guard let data = try? NSKeyedArchiver.archivedData(
        withRootObject: NSColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 1.0),
        requiringSecureCoding: true
    ) else { return Data() }
    return data
}()

final class UserSettings: ObservableObject {
    @AppStorage("sourceLanguage") var sourceLanguage: String = "en-US"
    @AppStorage("targetLanguage") var targetLanguage: String = "ko-KR"
    @AppStorage("fontSize") var fontSize: Double = 20
    @AppStorage("fontColorData") private var fontColorData: Data = defaultWhiteColorData
    @AppStorage("backgroundColorData") private var backgroundColorData: Data = defaultBlackColorData
    @AppStorage("backgroundOpacity") var backgroundOpacity: Double = 0.5
    @AppStorage("showOriginalText") var showOriginalText: Bool = true
    @AppStorage("showTranslation") var showTranslation: Bool = true
    @AppStorage("overlayWidth") var overlayWidth: Double = 600
    @AppStorage("overlayHeight") var overlayHeight: Double = 200
    @AppStorage("saveSessionHistory") var saveSessionHistory: Bool = true
    @AppStorage("sessionWindowAlwaysOnTop") var sessionWindowAlwaysOnTop: Bool = false
    @AppStorage("useOnDeviceRecognition") var useOnDeviceRecognition: Bool = true
    @AppStorage("allowOnlineTranslationFallback") var allowOnlineTranslationFallback: Bool = false
    @AppStorage("maxSubtitleLines") var maxSubtitleLines: Double = 3
    @AppStorage("subtitleExpirySeconds") var subtitleExpirySeconds: Double = 20
    @AppStorage("overlayLocked") var overlayLocked: Bool = true
    @AppStorage("speechPauseSeconds") var speechPauseSeconds: Double = 3.0
    @AppStorage("translatedFontSize") var translatedFontSize: Double = 20
    @AppStorage("translatedFontColorData") private var translatedFontColorData: Data = defaultCyanColorData
    @AppStorage("overlayFrameX") var overlayFrameX: Double = 200
    @AppStorage("overlayFrameY") var overlayFrameY: Double = 200
    @AppStorage("overlayFrameSaved") var overlayFrameSaved: Bool = false

    // Display mode: "combined" (single window) or "split" (recognition + translation)
    @AppStorage("overlayDisplayMode") var overlayDisplayMode: String = "split"

    // Second overlay (translation window) frame
    @AppStorage("overlay2FrameX") var overlay2FrameX: Double = 200
    @AppStorage("overlay2FrameY") var overlay2FrameY: Double = 450
    @AppStorage("overlay2Width") var overlay2Width: Double = 600
    @AppStorage("overlay2Height") var overlay2Height: Double = 200
    @AppStorage("overlay2FrameSaved") var overlay2FrameSaved: Bool = false
    @AppStorage("overlay2Locked") var overlay2Locked: Bool = true

    init() {
        sanitizeStoredSettings()
    }

    var fontColor: Color {
        get { Self.decodeColor(fontColorData) ?? .white }
        set { fontColorData = Self.encodeColor(newValue) }
    }

    var backgroundColor: Color {
        get { Self.decodeColor(backgroundColorData) ?? .black }
        set { backgroundColorData = Self.encodeColor(newValue) }
    }

    var translatedFontColor: Color {
        get { Self.decodeColor(translatedFontColorData) ?? Color(red: 0.6, green: 0.9, blue: 1.0) }
        set { translatedFontColorData = Self.encodeColor(newValue) }
    }

    var safeFontSize: Double {
        Self.clamped(fontSize, min: 12, max: 72, fallback: 20)
    }

    var safeTranslatedFontSize: Double {
        Self.clamped(translatedFontSize, min: 12, max: 72, fallback: 20)
    }

    var safeBackgroundOpacity: Double {
        Self.clamped(backgroundOpacity, min: 0, max: 1, fallback: 0.5)
    }

    var safeMaxSubtitleLines: Double {
        Self.clamped(maxSubtitleLines, min: 1, max: 10, fallback: 3)
    }

    var safeSubtitleExpirySeconds: Double {
        Self.clamped(subtitleExpirySeconds, min: 3, max: 60, fallback: 20)
    }

    var safeSpeechPauseSeconds: Double {
        Self.clamped(speechPauseSeconds, min: 0.5, max: 5, fallback: 3)
    }

    private func sanitizeStoredSettings() {
        if sourceLanguage != "auto", SupportedLanguage(rawValue: sourceLanguage) == nil {
            sourceLanguage = "en-US"
        }
        if SupportedLanguage(rawValue: targetLanguage) == nil {
            targetLanguage = "ko-KR"
        }
        if overlayDisplayMode != "combined", overlayDisplayMode != "split" {
            overlayDisplayMode = "split"
        }
        if !showOriginalText && !showTranslation {
            showTranslation = true
        }
        fontSize = safeFontSize
        translatedFontSize = safeTranslatedFontSize
        backgroundOpacity = safeBackgroundOpacity
        maxSubtitleLines = safeMaxSubtitleLines
        subtitleExpirySeconds = safeSubtitleExpirySeconds
        speechPauseSeconds = safeSpeechPauseSeconds
        sanitizeOverlayFrameValues()
    }

    private func sanitizeOverlayFrameValues() {
        overlayFrameX = Self.finite(overlayFrameX, fallback: 200)
        overlayFrameY = Self.finite(overlayFrameY, fallback: 200)
        overlayWidth = Self.clamped(overlayWidth, min: 200, max: 3000, fallback: 600)
        overlayHeight = Self.clamped(overlayHeight, min: 100, max: 2000, fallback: 200)
        overlay2FrameX = Self.finite(overlay2FrameX, fallback: 200)
        overlay2FrameY = Self.finite(overlay2FrameY, fallback: 450)
        overlay2Width = Self.clamped(overlay2Width, min: 200, max: 3000, fallback: 600)
        overlay2Height = Self.clamped(overlay2Height, min: 100, max: 2000, fallback: 200)
    }

    // MARK: - Color Serialization

    private static func encodeColor(_ color: Color) -> Data {
        let resolved = NSColor(color)
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: resolved,
            requiringSecureCoding: true
        ) else { return Data() }
        return data
    }

    private static func decodeColor(_ data: Data) -> Color? {
        guard !data.isEmpty,
              let nsColor = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSColor.self,
                from: data
              ) else { return nil }
        return Color(nsColor)
    }

    private static func clamped(_ value: Double, min: Double, max: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(max, Swift.max(min, value))
    }

    private static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }
}
