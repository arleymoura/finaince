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
    private let languageDefaultsKey = "app.language"
    private let cloudLanguageKey = "icloud.app.language.v2"
    private let ubiquitousStore = NSUbiquitousKeyValueStore.default
    private var ubiquitousObserver: NSObjectProtocol?

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: languageDefaultsKey)
            ubiquitousStore.set(language.rawValue, forKey: cloudLanguageKey)
            ubiquitousStore.synchronize()
        }
    }

    /// Resolved language — never .system
    var effective: AppLanguage {
        language == .system ? Self.preferredSupportedSystemLanguage() : language
    }

    private init() {
        ubiquitousStore.synchronize()

        let storedRaw = UserDefaults.standard.string(forKey: languageDefaultsKey)
        let cloudRaw = ubiquitousStore.string(forKey: cloudLanguageKey)
        let storedLanguage = storedRaw.flatMap(AppLanguage.init(rawValue:))
        let cloudLanguage = cloudRaw.flatMap(AppLanguage.init(rawValue:))
        let isConfiguredDevice = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let resolvedLanguage: AppLanguage

        if let storedLanguage, storedLanguage != .system {
            resolvedLanguage = storedLanguage
        } else if isConfiguredDevice, let cloudLanguage, cloudLanguage != .system {
            resolvedLanguage = cloudLanguage
        } else {
            resolvedLanguage = Self.preferredSupportedSystemLanguage()
        }

        DebugLaunchLog.log("🌐 [Language] init local=\(storedRaw ?? "nil") cloud=\(cloudRaw ?? "nil") configured=\(isConfiguredDevice) resolved=\(resolvedLanguage.rawValue)")

        UserDefaults.standard.set(resolvedLanguage.rawValue, forKey: languageDefaultsKey)
        self.language = resolvedLanguage

        if cloudRaw == nil, isConfiguredDevice {
            ubiquitousStore.set(resolvedLanguage.rawValue, forKey: cloudLanguageKey)
            ubiquitousStore.synchronize()
            DebugLaunchLog.log("🌐 [Language] seeded cloud language with \(resolvedLanguage.rawValue)")
        }

        ubiquitousObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { [weak self] _ in
            self?.applyCloudLanguageIfAvailable()
        }
    }

    deinit {
        if let ubiquitousObserver {
            NotificationCenter.default.removeObserver(ubiquitousObserver)
        }
    }

    private static func preferredSupportedSystemLanguage() -> AppLanguage {
        for preferredIdentifier in Locale.preferredLanguages {
            let normalized = preferredIdentifier.lowercased()
            if normalized.hasPrefix("pt") { return .ptBR }
            if normalized.hasPrefix("es") { return .es }
            if normalized.hasPrefix("en") { return .en }
        }

        let fallbackCode = Locale.current.language.languageCode?.identifier ?? "en"
        switch fallbackCode {
        case "pt": return .ptBR
        case "es": return .es
        case "en": return .en
        default:   return .en
        }
    }

    func syncFromCloud() {
        ubiquitousStore.synchronize()
        let cloudRaw = ubiquitousStore.string(forKey: cloudLanguageKey) ?? "nil"
        let isConfiguredDevice = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        DebugLaunchLog.log("🌐 [Language] syncFromCloud current=\(language.rawValue) cloud=\(cloudRaw) configured=\(isConfiguredDevice)")
        applyCloudLanguageIfAvailable()
    }

    private func applyCloudLanguageIfAvailable() {
        let isConfiguredDevice = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard isConfiguredDevice else {
            return
        }

        guard let cloudRaw = ubiquitousStore.string(forKey: cloudLanguageKey),
              let cloudLanguage = AppLanguage(rawValue: cloudRaw),
              cloudLanguage != .system,
              cloudLanguage != language else {
            return
        }

        DebugLaunchLog.log("🌐 [Language] applying cloud language \(cloudLanguage.rawValue) over \(language.rawValue)")
        language = cloudLanguage
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
