import Foundation
import SwiftData

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    /// On-device Apple Intelligence — sem chave de API, 100% privado
    case local     = "local"
    case groq      = "groq"
    case deepseek  = "deepseek"
    case anthropic = "anthropic"
    case openai    = "openai"
    case gemini    = "gemini"
    case openrouter = "openrouter"
    case cerebras  = "cerebras"
    case huggingface = "huggingface"
    case cohere    = "cohere"
    case mistral   = "mistral"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local:     return "Apple Intelligence"
        case .groq:      return "Groq"
        case .deepseek:  return "DeepSeek"
        case .anthropic: return "Claude"
        case .openai:    return "ChatGPT"
        case .gemini:    return "Gemini"
        case .openrouter: return "OpenRouter"
        case .cerebras:  return "Cerebras"
        case .huggingface: return "Hugging Face"
        case .cohere:    return "Cohere"
        case .mistral:   return "Mistral"
        }
    }

    var defaultModel: String {
        switch self {
        case .local:     return "apple-on-device"
        case .groq:      return "llama-3.3-70b-versatile"
        case .deepseek:  return "deepseek-chat"
        case .anthropic: return "claude-sonnet-4-6"
        case .openai:    return "gpt-4o"
        case .gemini:    return "gemini-2.0-flash-lite"
        case .openrouter: return "meta-llama/llama-3.3-70b-instruct:free"
        case .cerebras:  return "llama3.1-8b"
        case .huggingface: return "meta-llama/Llama-3.1-8B-Instruct"
        case .cohere:    return "command-r"
        case .mistral:   return "mistral-small-latest"
        }
    }

    var availableModels: [String] {
        switch self {
        case .local:     return ["apple-on-device"]
        case .groq:      return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "gemma2-9b-it"]
        case .deepseek:  return ["deepseek-chat", "deepseek-reasoner"]
        case .anthropic: return ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
        case .openai:    return ["gpt-4o", "gpt-4o-mini"]
        case .gemini:    return ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-2.5-pro-preview-05-06"]
        case .openrouter: return [
            "meta-llama/llama-3.3-70b-instruct:free",
            "qwen/qwen-2.5-72b-instruct:free",
            "google/gemma-3-27b-it:free",
            "mistralai/mistral-small-3.1-24b-instruct:free"
        ]
        case .cerebras:  return ["llama3.1-8b", "llama-3.3-70b"]
        case .huggingface: return [
            "meta-llama/Llama-3.1-8B-Instruct",
            "Qwen/Qwen2.5-72B-Instruct",
            "mistralai/Mistral-7B-Instruct-v0.3"
        ]
        case .cohere:    return ["command-r", "command-r-plus", "command-a-03-2025"]
        case .mistral:   return ["mistral-small-latest", "mistral-medium-latest", "mistral-large-latest"]
        }
    }

    /// Local não precisa de chave de API
    var requiresAPIKey: Bool { self != .local }

    /// Provedores que aceitam imagens nativas na API (vision / multimodal).
    var supportsVision: Bool {
        switch self {
        case .openai, .anthropic, .gemini: return true
        case .groq, .deepseek, .local, .openrouter, .cerebras, .huggingface, .cohere, .mistral:
            return false
        }
    }

    var keychainKey: String { "finaince.ai.apikey.\(rawValue)" }

    var apiKeyHint: String {
        switch self {
        case .local:     return ""
        case .groq:      return "Obtenha em console.groq.com"
        case .deepseek:  return "Obtenha em platform.deepseek.com"
        case .anthropic: return "Obtenha em console.anthropic.com"
        case .openai:    return "Obtenha em platform.openai.com"
        case .gemini:    return "Obtenha em aistudio.google.com"
        case .openrouter: return "Obtenha em openrouter.ai"
        case .cerebras:  return "Obtenha em cloud.cerebras.ai"
        case .huggingface: return "Obtenha em huggingface.co/settings/tokens"
        case .cohere:    return "Obtenha em dashboard.cohere.com"
        case .mistral:   return "Obtenha em console.mistral.ai"
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
    var id: UUID = UUID()
    var provider: AIProvider = AIProvider.local
    var model: String = ""
    var isConfigured: Bool = false
    // api_key armazenada exclusivamente no iOS Keychain — nunca aqui

    var family: Family?

    init(provider: AIProvider = .local) {
        self.id = UUID()
        self.provider = provider
        self.model = provider.defaultModel
        self.isConfigured = false
    }
}

// MARK: - AIAnalysis

@Model
final class AIAnalysis {
    var id: UUID = UUID()
    var monthRef: String = ""
    var generatedAt: Date = Date()
    var provider: String = ""
    var type: AnalysisType = AnalysisType.monthlySummary
    var content: String = ""

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
