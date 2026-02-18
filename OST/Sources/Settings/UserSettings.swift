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
    @AppStorage("fontSize") var fontSize: Double = 24
    @AppStorage("fontColorData") private var fontColorData: Data = defaultWhiteColorData
    @AppStorage("backgroundColorData") private var backgroundColorData: Data = defaultBlackColorData
    @AppStorage("backgroundOpacity") var backgroundOpacity: Double = 0.7
    @AppStorage("showOriginalText") var showOriginalText: Bool = true
    @AppStorage("showTranslation") var showTranslation: Bool = true
    @AppStorage("overlayWidth") var overlayWidth: Double = 600
    @AppStorage("overlayHeight") var overlayHeight: Double = 200
    @AppStorage("saveSessionHistory") var saveSessionHistory: Bool = true
    @AppStorage("sessionWindowAlwaysOnTop") var sessionWindowAlwaysOnTop: Bool = false
    @AppStorage("useOnDeviceRecognition") var useOnDeviceRecognition: Bool = true
    @AppStorage("maxSubtitleLines") var maxSubtitleLines: Double = 3
    @AppStorage("subtitleExpirySeconds") var subtitleExpirySeconds: Double = 10
    @AppStorage("overlayLocked") var overlayLocked: Bool = true
    @AppStorage("speechPauseSeconds") var speechPauseSeconds: Double = 2.0
    @AppStorage("translatedFontSize") var translatedFontSize: Double = 20
    @AppStorage("translatedFontColorData") private var translatedFontColorData: Data = defaultCyanColorData
    @AppStorage("overlayFrameX") var overlayFrameX: Double = 200
    @AppStorage("overlayFrameY") var overlayFrameY: Double = 200
    @AppStorage("overlayFrameSaved") var overlayFrameSaved: Bool = false

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
