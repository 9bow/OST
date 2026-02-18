import SwiftUI
import Translation

enum SupportedLanguage: String, CaseIterable, Identifiable {
    case english = "en-US"
    case chineseSimplified = "zh-Hans"
    case japanese = "ja-JP"
    case korean = "ko-KR"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:          return "English"
        case .chineseSimplified: return "中文（简体）"
        case .japanese:         return "日本語"
        case .korean:           return "한국어"
        }
    }

    var flagEmoji: String {
        switch self {
        case .english:          return "🇺🇸"
        case .chineseSimplified: return "🇨🇳"
        case .japanese:         return "🇯🇵"
        case .korean:           return "🇰🇷"
        }
    }

    /// Locale identifier for SFSpeechRecognizer (BCP-47 with region).
    var speechLocale: Locale {
        switch self {
        case .english:          return Locale(identifier: "en-US")
        case .chineseSimplified: return Locale(identifier: "zh-CN")
        case .japanese:         return Locale(identifier: "ja-JP")
        case .korean:           return Locale(identifier: "ko-KR")
        }
    }

    /// Locale.Language for the Translation framework.
    var translationLocale: Locale.Language {
        switch self {
        case .english:          return Locale.Language(identifier: "en")
        case .chineseSimplified: return Locale.Language(identifier: "zh-Hans")
        case .japanese:         return Locale.Language(identifier: "ja")
        case .korean:           return Locale.Language(identifier: "ko")
        }
    }
}
