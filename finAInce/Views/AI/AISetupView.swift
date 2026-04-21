import SwiftUI
import SwiftData

// MARK: - View-layer metadata for each provider (internal — usada em Setup e Settings)

extension AIProvider {
    var isFree: Bool {
        switch self {
        case .local, .gemini, .groq, .openrouter, .cerebras, .huggingface, .cohere:
            return true
        case .deepseek, .anthropic, .openai, .mistral:
            return false
        }
    }

    var accentColor: Color {
        switch self {
        case .local: return .purple
        default:     return Color.accentColor
        }
    }

    var iconName: String {
        switch self {
        case .local:     return "lock.shield.fill"
        case .groq:      return "bolt.fill"
        case .deepseek:  return "waveform.circle.fill"
        case .gemini:    return "star.fill"
        case .anthropic: return "brain"
        case .openai:    return "sparkles"
        case .openrouter: return "point.3.connected.trianglepath.dotted"
        case .cerebras:  return "speedometer"
        case .huggingface: return "face.smiling"
        case .cohere:    return "text.bubble.fill"
        case .mistral:   return "wind"
        }
    }

    var cardSubtitle: String {
        switch self {
        case .local:     return t("ai.provider.local.subtitle")
        case .groq:      return t("ai.provider.groq.subtitle")
        case .deepseek:  return t("ai.provider.deepseek.subtitle")
        case .gemini:    return t("ai.provider.gemini.subtitle")
        case .anthropic: return t("ai.provider.anthropic.subtitle")
        case .openai:    return t("ai.provider.openai.subtitle")
        case .openrouter: return t("ai.provider.openrouter.subtitle")
        case .cerebras:  return t("ai.provider.cerebras.subtitle")
        case .huggingface: return t("ai.provider.huggingface.subtitle")
        case .cohere:    return t("ai.provider.cohere.subtitle")
        case .mistral:   return t("ai.provider.mistral.subtitle")
        }
    }

    var setupURL: URL {
        switch self {
        case .local:     return URL(string: "App-Prefs:root=SIRI")!
        case .groq:      return URL(string: "https://console.groq.com/keys")!
        case .deepseek:  return URL(string: "https://platform.deepseek.com/api_keys")!
        case .gemini:    return URL(string: "https://aistudio.google.com/apikey")!
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai:    return URL(string: "https://platform.openai.com/api-keys")!
        case .openrouter: return URL(string: "https://openrouter.ai/keys")!
        case .cerebras:  return URL(string: "https://cloud.cerebras.ai/platform")!
        case .huggingface: return URL(string: "https://huggingface.co/settings/tokens")!
        case .cohere:    return URL(string: "https://dashboard.cohere.com/api-keys")!
        case .mistral:   return URL(string: "https://console.mistral.ai/api-keys")!
        }
    }

    var setupButtonLabel: String {
        switch self {
        case .local:     return t("ai.provider.local.open")
        case .groq:      return t("ai.provider.groq.open")
        case .deepseek:  return t("ai.provider.deepseek.open")
        case .gemini:    return t("ai.provider.gemini.open")
        case .anthropic: return t("ai.provider.anthropic.open")
        case .openai:    return t("ai.provider.openai.open")
        case .openrouter: return t("ai.provider.openrouter.open")
        case .cerebras:  return t("ai.provider.cerebras.open")
        case .huggingface: return t("ai.provider.huggingface.open")
        case .cohere:    return t("ai.provider.cohere.open")
        case .mistral:   return t("ai.provider.mistral.open")
        }
    }

    var setupSteps: [(icon: String, text: String)] {
        switch self {
        case .local:
            return [
                ("iphone",           t("ai.provider.local.step1")),
                ("brain",            t("ai.provider.local.step2")),
                ("checkmark.circle", t("ai.provider.local.step3")),
            ]
        case .groq:
            return [
                ("person.badge.plus", t("ai.provider.groq.step1")),
                ("key.horizontal",    t("ai.provider.groq.step2")),
                ("doc.on.clipboard",  t("ai.provider.groq.step3")),
            ]
        case .deepseek:
            return [
                ("person.badge.plus", t("ai.provider.deepseek.step1")),
                ("key.horizontal",    t("ai.provider.deepseek.step2")),
                ("doc.on.clipboard",  t("ai.provider.deepseek.step3")),
            ]
        case .gemini:
            return [
                ("person.circle",    t("ai.provider.gemini.step1")),
                ("key.horizontal",   t("ai.provider.gemini.step2")),
                ("doc.on.clipboard", t("ai.provider.gemini.step3")),
            ]
        case .anthropic:
            return [
                ("person.badge.plus", t("ai.provider.anthropic.step1")),
                ("creditcard",        t("ai.provider.anthropic.step2")),
                ("key.horizontal",    t("ai.provider.anthropic.step3")),
                ("doc.on.clipboard",  t("ai.provider.anthropic.step4")),
            ]
        case .openai:
            return [
                ("person.badge.plus", t("ai.provider.openai.step1")),
                ("creditcard",        t("ai.provider.openai.step2")),
                ("key.horizontal",    t("ai.provider.openai.step3")),
                ("doc.on.clipboard",  t("ai.provider.openai.step4")),
            ]
        case .openrouter:
            return [
                ("person.circle",    t("ai.provider.openrouter.step1")),
                ("key.horizontal",   t("ai.provider.openrouter.step2")),
                ("doc.on.clipboard", t("ai.provider.openrouter.step3")),
            ]
        case .cerebras:
            return [
                ("person.circle",    t("ai.provider.cerebras.step1")),
                ("key.horizontal",   t("ai.provider.cerebras.step2")),
                ("doc.on.clipboard", t("ai.provider.cerebras.step3")),
            ]
        case .huggingface:
            return [
                ("person.circle",    t("ai.provider.huggingface.step1")),
                ("key.horizontal",   t("ai.provider.huggingface.step2")),
                ("doc.on.clipboard", t("ai.provider.huggingface.step3")),
            ]
        case .cohere:
            return [
                ("person.circle",    t("ai.provider.cohere.step1")),
                ("key.horizontal",   t("ai.provider.cohere.step2")),
                ("doc.on.clipboard", t("ai.provider.cohere.step3")),
            ]
        case .mistral:
            return [
                ("person.circle",    t("ai.provider.mistral.step1")),
                ("creditcard",       t("ai.provider.mistral.step2")),
                ("key.horizontal",   t("ai.provider.mistral.step3")),
                ("doc.on.clipboard", t("ai.provider.mistral.step4")),
            ]
        }
    }

    var setupWarning: String? {
        switch self {
        case .local:       return nil
        case .groq:        return nil
        case .deepseek:    return nil
        case .gemini:      return nil
        case .cerebras:    return nil
        case .cohere:      return t("ai.provider.cohere.warning")
        case .huggingface: return t("ai.provider.huggingface.warning")
        case .openrouter:  return t("ai.provider.openrouter.warning")
        case .mistral:     return t("ai.provider.mistral.warning")
        case .anthropic:   return t("ai.provider.anthropic.warning")
        case .openai:      return t("ai.provider.openai.warning")
        }
    }

    func modelDisplayName(_ id: String) -> String {
        let map: [String: String] = [
            "apple-on-device": "Apple Intelligence",
            "deepseek-chat": "V3 (Chat)",
            "deepseek-reasoner": "R1 (Raciocínio)",
            "claude-opus-4-6": "Opus",
            "claude-sonnet-4-6": "Sonnet",
            "claude-haiku-4-5-20251001": "Haiku",
            "gpt-4o": "GPT-4o",
            "gpt-4o-mini": "GPT-4o mini",
            "gemini-2.0-flash": "2.0 Flash",
            "gemini-2.0-flash-lite": "2.0 Flash Lite",
            "gemini-2.5-pro-preview-05-06": "2.5 Pro",
            "meta-llama/llama-3.3-70b-instruct:free": "Llama 3.3 70B Free",
            "qwen/qwen-2.5-72b-instruct:free": "Qwen 2.5 72B Free",
            "google/gemma-3-27b-it:free": "Gemma 3 27B Free",
            "mistralai/mistral-small-3.1-24b-instruct:free": "Mistral Small Free",
            "llama3.1-8b": "Llama 3.1 8B",
            "llama-3.3-70b": "Llama 3.3 70B",
            "meta-llama/Llama-3.1-8B-Instruct": "Llama 3.1 8B",
            "Qwen/Qwen2.5-72B-Instruct": "Qwen 2.5 72B",
            "mistralai/Mistral-7B-Instruct-v0.3": "Mistral 7B",
            "command-r": "Command R",
            "command-r-plus": "Command R+",
            "command-a-03-2025": "Command A",
            "mistral-small-latest": "Mistral Small",
            "mistral-medium-latest": "Mistral Medium",
            "mistral-large-latest": "Mistral Large"
        ]
        return map[id] ?? id
    }
}

// Provedores na nuvem — exibidos na seção "Avançado"
let providerDisplayOrder: [AIProvider] = [.gemini, .openrouter, .cerebras, .huggingface, .cohere, .groq, .deepseek, .mistral, .anthropic, .openai]

// Todos os provedores exibidos nas configurações do perfil.
let settingsProviderDisplayOrder: [AIProvider] = [.local] + providerDisplayOrder

// MARK: - Main View

struct AISetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingSettings: [AISettings]

    @State private var selectedProvider: AIProvider = .local
    @State private var selectedModel: String = AIProvider.local.defaultModel
    @State private var apiKey: String = ""
    @State private var isKeyVisible: Bool = true
    @State private var showHelp: Bool = false
    @State private var localAvailability: LocalAIAvailability = .requiresNewerOS

    private var canSave: Bool {
        selectedProvider == .local || !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerView

                    VStack(spacing: 20) {
                        // ── IA local (hero) ─────────────────────────────
                        localHeroSection

                        // ── Divisor ─────────────────────────────────────
                        cloudDivider

                        // ── Provedores na nuvem ─────────────────────────
                        cloudSection
                    }
                    .padding(.horizontal)

                    // Seções de configuração de nuvem (apenas quando um cloud está selecionado)
                    if selectedProvider != .local {
                        VStack(spacing: 16) {
                            modelSection
                            apiKeySection
                            helpSection
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(t("ai.setup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.save")) { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: selectedProvider)
        }
        .task { refreshLocalAvailability() }
        .onAppear { loadExisting() }
        .onChange(of: selectedProvider) { _, newProvider in
            // Clear apiKey and load fresh from Keychain for the new provider
            apiKey = KeychainHelper.load(forKey: newProvider.keychainKey) ?? ""
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.purple.opacity(0.15), .blue.opacity(0.15)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 88, height: 88)
                Image(systemName: "brain")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .top, endPoint: .bottom
                    ))
            }
            Text(t("ai.setupTitle"))
                .font(.title3.bold())
            Text(t("ai.setupDesc"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
        .padding(.horizontal, 24)
    }

    // MARK: - Local Hero

    private var localHeroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(t("ai.recommended"))
            localHeroCard
        }
    }

    private var localHeroCard: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedProvider = .local
                selectedModel = AIProvider.local.defaultModel
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(
                                colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 52, height: 52)
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundStyle(LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .top, endPoint: .bottom
                            ))
                    }

                    // Title + badges
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(t("ai.onDevice"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(t("ai.noSetup"))
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.12))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                        Text(t("ai.onDeviceDesc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: selectedProvider == .local ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedProvider == .local ? Color.accentColor : Color.secondary.opacity(0.35))
                }

                // Availability badge
                localAvailabilityBadge
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                selectedProvider == .local ? Color.purple : Color.clear,
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var localAvailabilityBadge: some View {
        HStack(spacing: 6) {
            switch localAvailability {
            case .available:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(t("ai.localAvailable"))
                    .foregroundStyle(.green)
            case .needsAppleIntelligence:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Text(t("ai.localNeedsEnable"))
                    .foregroundStyle(.orange)
            case .deviceNotEligible:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(t("ai.localDeviceNotEligible"))
                    .foregroundStyle(.red)
            case .requiresNewerOS:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                Text(t("ai.localRequiresNewerOS"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(localAvailabilityBadgeBackground)
        .clipShape(Capsule())
    }

    private var localAvailabilityBadgeBackground: Color {
        switch localAvailability {
        case .available:             return .green.opacity(0.1)
        case .needsAppleIntelligence: return .orange.opacity(0.1)
        case .deviceNotEligible,
             .requiresNewerOS:       return Color(.tertiarySystemBackground)
        }
    }

    // MARK: - Cloud divider

    private var cloudDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color(.separator))
            Text(t("ai.orCloud"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color(.separator))
        }
    }

    // MARK: - Cloud providers

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(t("ai.advanced"))
            VStack(spacing: 8) {
                ForEach(providerDisplayOrder) { provider in
                    ProviderCardView(provider: provider, isSelected: selectedProvider == provider) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedProvider = provider
                            selectedModel = provider.defaultModel
                            // apiKey will be loaded via onChange(of: selectedProvider)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Model (cloud only)

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(t("ai.model"))
            HStack {
                Text(t("ai.version"))
                    .font(.subheadline)
                Spacer()
                Picker(t("ai.model"), selection: $selectedModel) {
                    ForEach(selectedProvider.availableModels, id: \.self) { model in
                        Text(selectedProvider.modelDisplayName(model)).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedProvider) { _, new in
                    selectedModel = new.defaultModel
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - API Key (cloud only)

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(t("ai.apiKey"))
            HStack(spacing: 10) {
                Group {
                    if isKeyVisible {
                        TextField(t("ai.apiKeyPlaceholder"), text: $apiKey)
                    } else {
                        SecureField(t("ai.apiKeyPlaceholder"), text: $apiKey)
                    }
                }
                .font(.system(.subheadline, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Button {
                    if let text = UIPasteboard.general.string {
                        apiKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(.secondary)
                }

                Button {
                    isKeyVisible.toggle()
                } label: {
                    Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Help (cloud only)

    private var helpSection: some View {
        DisclosureGroup(isExpanded: $showHelp) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(selectedProvider.setupSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(selectedProvider.accentColor)
                                    .frame(width: 22, height: 22)
                                Text("\(index + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            }
                            Text(step.text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 4)

                if let warning = selectedProvider.setupWarning {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Link(destination: selectedProvider.setupURL) {
                    Label(selectedProvider.setupButtonLabel, systemImage: "arrow.up.right.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(selectedProvider.accentColor.opacity(0.1))
                        .foregroundStyle(selectedProvider.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        } label: {
            Label(t("ai.howToApiKey"), systemImage: "questionmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.2), value: selectedProvider)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func refreshLocalAvailability() {
        localAvailability = LocalAIService.checkAvailability()
    }

    private func loadExisting() {
        guard let settings = existingSettings.first else { return }
        selectedProvider = settings.provider
        selectedModel = settings.model
        if settings.provider.requiresAPIKey {
            apiKey = KeychainHelper.load(forKey: settings.provider.keychainKey) ?? ""
        }
    }

    private func save() {
        // Salva chave apenas para provedores cloud
        if selectedProvider.requiresAPIKey {
            let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
            KeychainHelper.save(trimmed, forKey: selectedProvider.keychainKey)
        }

        let isConfigured = selectedProvider == .local
            ? localAvailability == .available
            : true

        if let settings = existingSettings.first {
            settings.provider = selectedProvider
            settings.model    = selectedModel
            settings.isConfigured = isConfigured
        } else {
            let settings = AISettings(provider: selectedProvider)
            settings.model        = selectedModel
            settings.isConfigured = isConfigured
            modelContext.insert(settings)
        }
        dismiss()
    }
}

// MARK: - Provider Card (cloud)

struct ProviderCardView: View {
    let provider: AIProvider
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(provider.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: provider.iconName)
                        .font(.title3)
                        .foregroundStyle(provider.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(provider.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if provider.isFree {
                            Text(t("ai.free"))
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                    Text(provider.cardSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
