import CoreGraphics
import Foundation

public struct RGBAColor: Codable, Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let secondary = RGBAColor(red: 0.72, green: 0.72, blue: 0.74)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)

    public func contrastRatio(against background: RGBAColor) -> Double {
        func luminance(_ color: RGBAColor) -> Double {
            func channel(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
        }
        let foreground = luminance(self)
        let backdrop = luminance(background)
        return (max(foreground, backdrop) + 0.05) / (min(foreground, backdrop) + 0.05)
    }
}

public enum OverlayLayout: String, Codable, CaseIterable, Sendable {
    case combined
    case split
}

public enum MicrophoneMode: String, Codable, CaseIterable, Sendable {
    case off
    case transcription
    case transcriptionAndTranslation

    public var isEnabled: Bool { self != .off }

    public func translates(_ source: AudioSource) -> Bool {
        source == .systemAudio || self == .transcriptionAndTranslation
    }
}

public enum SubtitleDisplayMode: String, Codable, CaseIterable, Sendable {
    case both
    case sourceOnly
    case translationOnly

    public var showsSource: Bool { self != .translationOnly }
    public var showsTranslation: Bool { self != .sourceOnly }
}

public enum SubtitleAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

public enum AppDisplayLanguage: String, Codable, CaseIterable, Sendable {
    case english
    case chinese
    case japanese
    case korean

    public var localeIdentifier: String {
        switch self {
        case .english: "en"
        case .chinese: "zh-Hans"
        case .japanese: "ja"
        case .korean: "ko"
        }
    }
}

public struct PreferencesSnapshot: Codable, Sendable, Equatable {
    public var sourceMode: SourceLanguageMode
    public var targetLanguage: SupportedLanguage
    public var chineseScriptPreference: ChineseScriptPreference
    public var transcriptionProvider: ProviderID
    public var translationProvider: ProviderID
    public var selectedASRModelID: String
    public var selectedTranslationModelID: String
    public var mlxTranslationPrompt: String
    public var transcriptionVocabulary: String
    public var microphoneMode: MicrophoneMode
    public var microphoneColor: RGBAColor
    public var overlayLayout: OverlayLayout
    public var subtitleDisplayMode: SubtitleDisplayMode
    public var overlayLocked: Bool
    public var sourceFontSize: Double
    public var translationFontSize: Double
    public var previewFontSize: Double
    public var sourceColor: RGBAColor
    public var translationColor: RGBAColor
    public var previewColor: RGBAColor
    public var backgroundColor: RGBAColor
    public var backgroundOpacity: Double
    public var overlayLineCount: Int
    public var endpointSilenceSeconds: Double
    public var subtitleAlignment: SubtitleAlignment
    public var appDisplayLanguage: AppDisplayLanguage
    public var sessionLoggingEnabled: Bool
    public var sessionLogDirectoryBookmark: Data?
    public var sessionLogDirectoryPath: String?

    public init(
        sourceMode: SourceLanguageMode = .fixed(.english),
        targetLanguage: SupportedLanguage = .korean,
        chineseScriptPreference: ChineseScriptPreference = .simplified,
        transcriptionProvider: ProviderID = .appleSpeech,
        translationProvider: ProviderID = .appleTranslation,
        selectedASRModelID: String = "mlx-community/Qwen3-ASR-0.6B-4bit",
        selectedTranslationModelID: String = "mlx-community/Qwen3-0.6B-4bit",
        mlxTranslationPrompt: String = MLXPromptDefaults.translation,
        transcriptionVocabulary: String = "",
        microphoneMode: MicrophoneMode = .off,
        microphoneColor: RGBAColor = RGBAColor(red: 0.35, green: 0.85, blue: 1),
        overlayLayout: OverlayLayout = .combined,
        subtitleDisplayMode: SubtitleDisplayMode = .both,
        overlayLocked: Bool = false,
        sourceFontSize: Double = 20,
        translationFontSize: Double = 28,
        previewFontSize: Double = 28,
        sourceColor: RGBAColor = .secondary,
        translationColor: RGBAColor = .white,
        previewColor: RGBAColor = .white,
        backgroundColor: RGBAColor = .black,
        backgroundOpacity: Double = 0.65,
        overlayLineCount: Int = 3,
        endpointSilenceSeconds: Double = 0.8,
        subtitleAlignment: SubtitleAlignment = .leading,
        appDisplayLanguage: AppDisplayLanguage = .english,
        sessionLoggingEnabled: Bool = false,
        sessionLogDirectoryBookmark: Data? = nil,
        sessionLogDirectoryPath: String? = nil
    ) {
        self.sourceMode = sourceMode
        self.targetLanguage = targetLanguage
        self.chineseScriptPreference = chineseScriptPreference
        self.transcriptionProvider = transcriptionProvider
        self.translationProvider = translationProvider
        self.selectedASRModelID = selectedASRModelID
        self.selectedTranslationModelID = selectedTranslationModelID
        self.mlxTranslationPrompt = String(mlxTranslationPrompt.prefix(4_000))
        self.transcriptionVocabulary = String(transcriptionVocabulary.prefix(TranscriptionVocabulary.maximumCharacters))
        self.microphoneMode = microphoneMode
        self.microphoneColor = microphoneColor
        self.overlayLayout = overlayLayout
        self.subtitleDisplayMode = subtitleDisplayMode
        self.overlayLocked = overlayLocked
        self.sourceFontSize = min(max(sourceFontSize, 12), 72)
        self.translationFontSize = min(max(translationFontSize, 12), 72)
        self.previewFontSize = min(max(previewFontSize, 12), 72)
        self.sourceColor = sourceColor
        self.translationColor = translationColor
        self.previewColor = previewColor
        self.backgroundColor = backgroundColor
        self.backgroundOpacity = min(max(backgroundOpacity, 0), 1)
        self.overlayLineCount = min(max(overlayLineCount, 2), 10)
        self.endpointSilenceSeconds = min(max(endpointSilenceSeconds, 0.4), 2)
        self.subtitleAlignment = subtitleAlignment
        self.appDisplayLanguage = appDisplayLanguage
        self.sessionLoggingEnabled = sessionLoggingEnabled
        self.sessionLogDirectoryBookmark = sessionLogDirectoryBookmark
        self.sessionLogDirectoryPath = sessionLogDirectoryPath
    }

    private enum CodingKeys: String, CodingKey {
        case sourceMode
        case targetLanguage
        case chineseScriptPreference
        case transcriptionProvider
        case translationProvider
        case selectedASRModelID
        case selectedTranslationModelID
        case mlxTranslationPrompt
        case transcriptionVocabulary
        case microphoneMode
        case microphoneColor
        case overlayLayout
        case subtitleDisplayMode
        case overlayLocked
        case sourceFontSize
        case translationFontSize
        case previewFontSize
        case sourceColor
        case translationColor
        case previewColor
        case backgroundColor
        case backgroundOpacity
        case overlayLineCount
        case endpointSilenceSeconds
        case subtitleAlignment
        case appDisplayLanguage
        case sessionLoggingEnabled
        case sessionLogDirectoryBookmark
        case sessionLogDirectoryPath
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let translationFontSize = try values.decodeIfPresent(Double.self, forKey: .translationFontSize) ?? 28
        let translationColor = try values.decodeIfPresent(RGBAColor.self, forKey: .translationColor) ?? .white
        self.init(
            sourceMode: try values.decodeIfPresent(SourceLanguageMode.self, forKey: .sourceMode) ?? .fixed(.english),
            targetLanguage: try values.decodeIfPresent(SupportedLanguage.self, forKey: .targetLanguage) ?? .korean,
            chineseScriptPreference: try values.decodeIfPresent(ChineseScriptPreference.self, forKey: .chineseScriptPreference) ?? .simplified,
            transcriptionProvider: try values.decodeIfPresent(ProviderID.self, forKey: .transcriptionProvider) ?? .appleSpeech,
            translationProvider: try values.decodeIfPresent(ProviderID.self, forKey: .translationProvider) ?? .appleTranslation,
            selectedASRModelID: try values.decodeIfPresent(String.self, forKey: .selectedASRModelID) ?? "mlx-community/Qwen3-ASR-0.6B-4bit",
            selectedTranslationModelID: try values.decodeIfPresent(String.self, forKey: .selectedTranslationModelID) ?? "mlx-community/Qwen3-0.6B-4bit",
            mlxTranslationPrompt: try values.decodeIfPresent(String.self, forKey: .mlxTranslationPrompt) ?? MLXPromptDefaults.translation,
            transcriptionVocabulary: try values.decodeIfPresent(String.self, forKey: .transcriptionVocabulary) ?? "",
            microphoneMode: try values.decodeIfPresent(MicrophoneMode.self, forKey: .microphoneMode) ?? .off,
            microphoneColor: try values.decodeIfPresent(RGBAColor.self, forKey: .microphoneColor) ?? RGBAColor(red: 0.35, green: 0.85, blue: 1),
            overlayLayout: try values.decodeIfPresent(OverlayLayout.self, forKey: .overlayLayout) ?? .combined,
            subtitleDisplayMode: try values.decodeIfPresent(SubtitleDisplayMode.self, forKey: .subtitleDisplayMode) ?? .both,
            overlayLocked: try values.decodeIfPresent(Bool.self, forKey: .overlayLocked) ?? true,
            sourceFontSize: try values.decodeIfPresent(Double.self, forKey: .sourceFontSize) ?? 20,
            translationFontSize: translationFontSize,
            previewFontSize: try values.decodeIfPresent(Double.self, forKey: .previewFontSize) ?? translationFontSize,
            sourceColor: try values.decodeIfPresent(RGBAColor.self, forKey: .sourceColor) ?? .secondary,
            translationColor: translationColor,
            previewColor: try values.decodeIfPresent(RGBAColor.self, forKey: .previewColor) ?? translationColor,
            backgroundColor: try values.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? .black,
            backgroundOpacity: try values.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.65,
            overlayLineCount: try values.decodeIfPresent(Int.self, forKey: .overlayLineCount) ?? 3,
            endpointSilenceSeconds: try values.decodeIfPresent(Double.self, forKey: .endpointSilenceSeconds) ?? 0.8,
            subtitleAlignment: try values.decodeIfPresent(SubtitleAlignment.self, forKey: .subtitleAlignment) ?? .leading,
            appDisplayLanguage: try values.decodeIfPresent(AppDisplayLanguage.self, forKey: .appDisplayLanguage) ?? .english,
            sessionLoggingEnabled: try values.decodeIfPresent(Bool.self, forKey: .sessionLoggingEnabled) ?? false,
            sessionLogDirectoryBookmark: try values.decodeIfPresent(Data.self, forKey: .sessionLogDirectoryBookmark),
            sessionLogDirectoryPath: try values.decodeIfPresent(String.self, forKey: .sessionLogDirectoryPath)
        )
    }
}

public enum OverlaySizing {
    public static let previewLineCount = 2

    public static func combinedSize(
        lineCount: Int,
        sourceFontSize: Double,
        translationFontSize: Double,
        previewFontSize: Double? = nil,
        displayMode: SubtitleDisplayMode = .both,
        microphoneMode: MicrophoneMode = .off,
        maximumHeight: Double
    ) -> CGSize {
        switch displayMode {
        case .sourceOnly:
            return sourceSize(lineCount: lineCount, fontSize: sourceFontSize, microphoneMode: microphoneMode, maximumHeight: maximumHeight)
        case .translationOnly:
            return translationSize(
                lineCount: lineCount,
                fontSize: translationFontSize,
                previewFontSize: previewFontSize,
                microphoneMode: microphoneMode,
                maximumHeight: maximumHeight
            )
        case .both:
            break
        }
        let confirmedLines = Double(min(max(lineCount, 2), 10))
        let previewLines = Double(previewLineCount)
        let sourcePreviewLines = previewLines * (microphoneMode.isEnabled ? 2 : 1)
        let translationPreviewLines = previewLines * (microphoneMode.translates(.microphone) ? 2 : 1)
        let requestedHeight = sourceFontSize * 1.25 * (confirmedLines + sourcePreviewLines)
            + translationFontSize * 1.25 * confirmedLines
            + (previewFontSize ?? translationFontSize) * 1.25 * translationPreviewLines
            + 52
        return CGSize(width: 720, height: cappedHeight(requestedHeight, maximumHeight: maximumHeight))
    }

    public static func sourceSize(
        lineCount: Int,
        fontSize: Double,
        microphoneMode: MicrophoneMode = .off,
        maximumHeight: Double
    ) -> CGSize {
        let lines = Double(min(max(lineCount, 2), 10) + previewLineCount * (microphoneMode.isEnabled ? 2 : 1))
        let requestedHeight = fontSize * 1.25 * lines + 28
        return CGSize(width: 720, height: cappedHeight(requestedHeight, maximumHeight: maximumHeight))
    }

    public static func translationSize(
        lineCount: Int,
        fontSize: Double,
        previewFontSize: Double? = nil,
        microphoneMode: MicrophoneMode = .off,
        maximumHeight: Double
    ) -> CGSize {
        let confirmedLines = Double(min(max(lineCount, 2), 10))
        let previewLines = Double(previewLineCount * (microphoneMode.translates(.microphone) ? 2 : 1))
        let requestedHeight = fontSize * 1.25 * confirmedLines
            + (previewFontSize ?? fontSize) * 1.25 * previewLines
            + 28
        return CGSize(width: 720, height: cappedHeight(requestedHeight, maximumHeight: maximumHeight))
    }

    private static func cappedHeight(_ requestedHeight: Double, maximumHeight: Double) -> Double {
        min(max(requestedHeight, 96), max(maximumHeight * 0.9, 96))
    }
}

public enum OverlayFrameRestorer {
    public static func restoredFrame(
        stored: CGRect?,
        visibleFrames: [CGRect],
        primaryVisibleFrame: CGRect,
        defaultSize: CGSize = CGSize(width: 720, height: 180)
    ) -> CGRect {
        let screens = visibleFrames.isEmpty ? [primaryVisibleFrame] : visibleFrames
        if let stored, let screen = screens.first(where: { $0.intersects(stored.insetBy(dx: 32, dy: 32)) }) {
            return clamp(stored, to: screen)
        }
        let width = min(max(defaultSize.width, 320), primaryVisibleFrame.width * 0.9)
        let height = min(max(defaultSize.height, 96), primaryVisibleFrame.height)
        return CGRect(
            x: primaryVisibleFrame.midX - width / 2,
            y: primaryVisibleFrame.minY + 48,
            width: width,
            height: height
        )
    }

    public static func clamp(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let width = min(max(frame.width, 320), visibleFrame.width * 0.9)
        let height = min(max(frame.height, 96), visibleFrame.height)
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
