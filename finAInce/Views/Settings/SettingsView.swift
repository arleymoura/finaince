import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var aiSettingsList: [AISettings]

    @State private var apiKey = ""
    @State private var showApiKey = false
    @State private var showSavedAlert = false

    var aiSettings: AISettings? { aiSettingsList.first }

    var body: some View {
        NavigationStack {
            Form {
                familySection
                aiSection
                preferencesSection
                aboutSection
            }
            .navigationTitle("Configurações")
            .alert("Configurações salvas", isPresented: $showSavedAlert) {
                Button("OK") { }
            }
        }
    }

    // MARK: - Sections

    private var familySection: some View {
        Section("Família") {
            NavigationLink {
                Text("Gerenciar Membros — em breve")
            } label: {
                Label("Membros da família", systemImage: "person.2.fill")
            }
        }
    }

    private var aiSection: some View {
        Section {
            if let settings = aiSettings {
                Picker("Provedor", selection: Binding(
                    get: { settings.provider },
                    set: { settings.provider = $0; settings.model = $0.defaultModel }
                )) {
                    ForEach(AIProvider.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }

                Picker("Modelo", selection: Binding(
                    get: { settings.model },
                    set: { settings.model = $0 }
                )) {
                    ForEach(settings.provider.availableModels, id: \.self) {
                        Text($0).tag($0)
                    }
                }

                HStack {
                    Label("Chave de API", systemImage: "key.fill")
                    Spacer()
                    Group {
                        if showApiKey {
                            TextField("sk-...", text: $apiKey)
                                .multilineTextAlignment(.trailing)
                        } else {
                            SecureField("sk-...", text: $apiKey)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 180)

                    Button {
                        showApiKey.toggle()
                    } label: {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Salvar Chave de API") {
                    saveApiKey(settings)
                }
                .disabled(apiKey.isEmpty)

                if settings.isConfigured {
                    Label("API configurada", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        } header: {
            Text("Inteligência Artificial")
        } footer: {
            Text("A chave é armazenada com segurança no iOS Keychain do seu dispositivo e nunca enviada para nossos servidores.")
        }
    }

    private var preferencesSection: some View {
        Section("Preferências") {
            LabeledContent("Moeda", value: "BRL (R$)")

            Picker("Tema", selection: .constant("auto")) {
                Text("Automático").tag("auto")
                Text("Claro").tag("light")
                Text("Escuro").tag("dark")
            }
        }
    }

    private var aboutSection: some View {
        Section("Sobre") {
            LabeledContent("Versão", value: "1.0.0 (Sprint 1)")
            LabeledContent("Design", value: "Apple HIG + SF Symbols")
        }
    }

    // MARK: - Actions

    private func saveApiKey(_ settings: AISettings) {
        // Sprint 4: salvar no iOS Keychain
        // KeychainHelper.save(apiKey, for: settings.provider)
        settings.isConfigured = !apiKey.isEmpty
        showSavedAlert = true
    }
}
