import Foundation
import SwiftUI

// MARK: - App Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system" // Legacy value. Do not show as a selectable option.
    case ptBR   = "pt-BR"
    case en     = "en"
    case es     = "es"

    static var allCases: [AppLanguage] { [.ptBR, .en, .es] }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Automático / Auto"
        case .ptBR:   return "Português (Brasil)"
        case .en:     return "English"
        case .es:     return "Español"
        }
    }

    var flag: String {
        switch self {
        case .system: return "🌐"
        case .ptBR:   return "🇧🇷"
        case .en:     return "🇺🇸"
        case .es:     return "🇪🇸"
        }
    }

    var locale: Locale {
        switch self {
        case .system: return .current
        case .ptBR:   return Locale(identifier: "pt_BR")
        case .en:     return Locale(identifier: "en_US")
        case .es:     return Locale(identifier: "es_419")
        }
    }

    var visionRecognitionLanguages: [String] {
        switch self {
        case .system:
            return LanguageManager.shared.effective.visionRecognitionLanguages
        case .ptBR:
            return ["pt-BR", "en-US"]
        case .en:
            return ["en-US", "pt-BR"]
        case .es:
            return ["es-ES", "en-US", "pt-BR"]
        }
    }
}

// MARK: - Language Manager

@Observable final class LanguageManager {
    static let shared = LanguageManager()

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "app.language") }
    }

    /// Resolved language — never .system
    var effective: AppLanguage {
        language == .system ? Self.preferredSupportedSystemLanguage() : language
    }

    private init() {
        let storedRaw = UserDefaults.standard.string(forKey: "app.language")
        let storedLanguage = storedRaw.flatMap(AppLanguage.init(rawValue:))
        let resolvedLanguage: AppLanguage

        if let storedLanguage, storedLanguage != .system {
            resolvedLanguage = storedLanguage
        } else {
            resolvedLanguage = Self.preferredSupportedSystemLanguage()
            UserDefaults.standard.set(resolvedLanguage.rawValue, forKey: "app.language")
        }

        self.language = resolvedLanguage
    }

    private static func preferredSupportedSystemLanguage() -> AppLanguage {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        switch code {
        case "pt": return .ptBR
        case "es": return .es
        case "en": return .en
        default:   return .en
        }
    }

    // MARK: Translation

    func t(_ key: String) -> String {
        let table: [String: String]
        switch effective {
        case .ptBR, .system: table = Strings.ptBR
        case .en:             table = Strings.en
        case .es:             table = Strings.es
        }
        return table[key] ?? key
    }

    /// Formatted translation — supports %@ and %d placeholders
    func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}

// MARK: - Global shorthand

/// Use `t("key")` anywhere in the app — no environment needed.
/// Re-rendering on language change is handled by the `.id(lm.language)` modifier in ContentView.
@inline(__always)
func t(_ key: String) -> String { LanguageManager.shared.t(key) }

@inline(__always)
func t(_ key: String, _ args: CVarArg...) -> String {
    String(format: LanguageManager.shared.t(key), arguments: args)
}
