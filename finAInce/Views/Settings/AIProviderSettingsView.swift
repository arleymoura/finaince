import SwiftUI
import SwiftData
import UIKit

struct AIProviderSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AISettings]

    @State private var editingProvider: AIProvider? = nil

    private var activeSettings: AISettings? {
        settingsList.first(where: { $0.isConfigured })
    }

    var body: some View {
        Form {
            introSection
            activeSection
            otherProvidersSection
        }
        .listSectionSpacing(.compact)
        .navigationTitle(t("settings.ai"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingProvider) { provider in
            AIKeyEditSheet(provider: provider, settings: activeSettings, modelContext: modelContext)
        }
    }

    // MARK: - Intro

    private var introSection: some View {
        Section {
            
            VStack(spacing: 12) {
                
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.purple.opacity(0.12), .blue.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 100, height: 100)

                    Image(systemName: "brain")
                        .font(.system(size: 44))
                        .foregroundStyle(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                }
                
                VStack(spacing: 8) {
                    Text(t("ai.setupTitle"))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(t("ai.setupDesc"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 0)
            .padding(.bottom, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        } header: { EmptyView() }
    }

    // MARK: - Provedor ativo

    private var activeSection: some View {
        Section {
            if let settings = activeSettings {
                // ── Row 1: identidade do provedor ─────────────────────────
                HStack(spacing: 12) {
                    providerIcon(settings.provider, size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(settings.provider.label)
                                .font(.subheadline.weight(.semibold))
                            if settings.provider.isFree {
                                Text(t("ai.free"))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(settings.provider.cardSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Badge "ativo"
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                        Text(t("ai.active"))
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.10))
                    .clipShape(Capsule())
                }

                // ── Row 2: seleção de modelo (linha própria = sem truncar) ─
                Picker(t("ai.model"), selection: Binding(
                    get: { settings.model },
                    set: { settings.model = $0 }
                )) {
                    ForEach(settings.provider.availableModels, id: \.self) { model in
                        Text(settings.provider.modelDisplayName(model)).tag(model)
                    }
                }

                // ── Row 3: chave de API (se necessário) ───────────────────
                if settings.provider.requiresAPIKey {
                    Button {
                        editingProvider = settings.provider
                    } label: {
                        HStack {
                            Label(t("ai.apiKey"), systemImage: "key.fill")
                            Spacer()
                            Text(t("common.configure"))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                // ── Row 4: desativar (botão explícito, sem swipe oculto) ──
                Button(role: .destructive) {
                    deactivateActiveProvider()
                } label: {
                    HStack {
                        Label(t("common.deactivate"), systemImage: "xmark.circle")
                        Spacer()
                    }
                }
            } else {
                Text(t("ai.notConfigured"))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(t("ai.providerActive"))
        }
    }

    // MARK: - Outros provedores

    private func hasSavedKey(for provider: AIProvider) -> Bool {
        guard !provider.requiresAPIKey else {
            let key = KeychainHelper.load(forKey: provider.keychainKey) ?? ""
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var otherProvidersSection: some View {
        Section {
            ForEach(settingsProviderDisplayOrder.filter { $0 != activeSettings?.provider }) { provider in
                otherProviderRow(provider)
            }
        } header: {
            Text(t("ai.otherProviders"))
        } footer: {
            Text(t("ai.providerFooter"))
        }
    }

    @ViewBuilder
    private func otherProviderRow(_ provider: AIProvider) -> some View {
        let hasKey = hasSavedKey(for: provider)
        HStack(spacing: 12) {
            providerIcon(provider, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.label)
                        .font(.subheadline.weight(.semibold))
                    if provider.isFree {
                        Text(t("ai.free"))
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                Text(provider.requiresAPIKey ? (hasKey ? t("ai.keySaved") : t("ai.notConfigured")) : t("ai.noApiKey"))
                    .font(.caption)
                    .foregroundStyle(hasKey ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            }

            Spacer()

            if hasKey {
                Button(t("common.use")) { activate(provider) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color.accentColor)
            }

            Button(provider.requiresAPIKey ? t("common.configure") : t("common.details")) {
                editingProvider = provider
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.gray)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingProvider = provider
        }
    }

    // MARK: - Helpers

    private func activate(_ provider: AIProvider) {
        settingsList.forEach { $0.isConfigured = false }

        if let existing = settingsList.first(where: { $0.provider == provider }) {
            existing.provider = provider
            if existing.model.isEmpty {
                existing.model = provider.defaultModel
            }
            existing.isConfigured = true
        } else if let activeSettings {
            activeSettings.provider = provider
            activeSettings.model = provider.defaultModel
            activeSettings.isConfigured = true
        } else {
            let newSettings = AISettings(provider: provider)
            newSettings.model = provider.defaultModel
            newSettings.isConfigured = true
            modelContext.insert(newSettings)
        }

        try? modelContext.save()
    }

    private func deactivateActiveProvider() {
        guard let activeSettings else { return }
        activeSettings.isConfigured = false
        try? modelContext.save()
    }

    private func providerIcon(_ provider: AIProvider, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(provider.accentColor.opacity(0.15))
                .frame(width: size, height: size)
            Image(systemName: provider.iconName)
                .font(size > 40 ? .title3 : .subheadline)
                .foregroundStyle(provider.accentColor)
        }
    }
}

// MARK: - AIKeyEditSheet

struct AIKeyEditSheet: View {
    let provider: AIProvider
    let settings: AISettings?
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var selectedModel: String = ""
    @State private var isKeyVisible: Bool = true
    @State private var showHelp: Bool = false
    @State private var makeActive: Bool = false

    private var isActive: Bool { settings?.provider == provider }
    private var canSave: Bool {
        !provider.requiresAPIKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Cabeçalho do provedor
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(provider.accentColor.opacity(0.15))
                                .frame(width: 52, height: 52)
                            Image(systemName: provider.iconName)
                                .font(.title2)
                                .foregroundStyle(provider.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(provider.label)
                                    .font(.headline)
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
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isActive {
                            Text(t("ai.active"))
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.12))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Modelo
                    VStack(alignment: .leading, spacing: 8) {
                            sectionLabel(t("ai.model"))
                        HStack {
                            Text(t("ai.version"))
                                .font(.subheadline)
                            Spacer()
                            Picker(t("ai.model"), selection: $selectedModel) {
                                ForEach(provider.availableModels, id: \.self) { model in
                                    Text(provider.modelDisplayName(model)).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if provider.requiresAPIKey {
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

                    // Tornar ativo (só aparece quando não é o ativo)
                    if !isActive {
                        Toggle(isOn: $makeActive) {
                            Label(t("ai.makeActive"), systemImage: "checkmark.circle")
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Ajuda
                    DisclosureGroup(isExpanded: $showHelp) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(provider.setupSteps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(provider.accentColor)
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

                            if let warning = provider.setupWarning {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(10)
                                .background(Color.orange.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            Link(destination: provider.setupURL) {
                                Label(provider.setupButtonLabel, systemImage: "arrow.up.right.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(provider.accentColor.opacity(0.1))
                                    .foregroundStyle(provider.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Label(provider.requiresAPIKey ? t("ai.howToKey") : t("ai.requirements"), systemImage: "questionmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle(t("ai.editProvider", provider.label))
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
        }
        .onAppear { loadExisting() }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func loadExisting() {
        selectedModel = (isActive ? settings?.model : nil) ?? provider.defaultModel
        apiKey = KeychainHelper.load(forKey: provider.keychainKey) ?? ""
        makeActive = isActive
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.requiresAPIKey {
            if trimmed.isEmpty {
                KeychainHelper.delete(forKey: provider.keychainKey)
            } else {
                KeychainHelper.save(trimmed, forKey: provider.keychainKey)
            }
        }

        if isActive, let settings {
            settings.model = selectedModel
            settings.isConfigured = true
        } else if makeActive {
            if let settings {
                settings.provider = provider
                settings.model = selectedModel
                settings.isConfigured = true
            } else {
                let s = AISettings(provider: provider)
                s.model = selectedModel
                s.isConfigured = true
                modelContext.insert(s)
            }
        }
        dismiss()
    }
}
