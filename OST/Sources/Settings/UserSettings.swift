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
    @AppStorage("maxSubtitleLines") var maxSubtitleLines: Double = 3
    @AppStorage("subtitleExpirySeconds") var subtitleExpirySeconds: Double = 20
    @AppStorage("overlayLocked") var overlayLocked: Bool = false
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
    @AppStorage("overlay2Locked") var overlay2Locked: Bool = false

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
}
