import Foundation
import SwiftData

enum AIProvider: String, Codable, CaseIterable {
    case openai    = "openai"
    case anthropic = "anthropic"

    var label: String {
        switch self {
        case .openai:    return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai:    return "gpt-4o"
        case .anthropic: return "claude-opus-4-6"
        }
    }

    var availableModels: [String] {
        switch self {
        case .openai:    return ["gpt-4o", "gpt-4o-mini"]
        case .anthropic: return ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
        }
    }
}

enum AnalysisType: String, Codable {
    case monthlySummary = "monthly_summary"
    case alert          = "alert"
    case projection     = "projection"
}

// MARK: - AISettings

@Model
final class AISettings {
    @Attribute(.unique) var id: UUID
    var provider: AIProvider
    var model: String
    var isConfigured: Bool
    // api_key armazenada exclusivamente no iOS Keychain — nunca aqui

    var family: Family?

    init(provider: AIProvider = .openai) {
        self.id = UUID()
        self.provider = provider
        self.model = provider.defaultModel
        self.isConfigured = false
    }
}

// MARK: - AIAnalysis

@Model
final class AIAnalysis {
    @Attribute(.unique) var id: UUID
    var monthRef: String       // ex: "2026-04"
    var generatedAt: Date
    var provider: String
    var type: AnalysisType
    var content: String        // resposta em markdown

    var family: Family?

    init(monthRef: String, provider: String, type: AnalysisType, content: String) {
        self.id = UUID()
        self.monthRef = monthRef
        self.generatedAt = Date()
        self.provider = provider
        self.type = type
        self.content = content
    }
}
