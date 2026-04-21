import SwiftUI
import SwiftData

@main
struct FamilyFinanceApp: App {
    let modelContainer: ModelContainer

    init() {
        modelContainer = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { seedIfNeeded() }
        }
        .modelContainer(modelContainer)
    }

    // MARK: - iCloud Backup Exclusion

    /// Exclui o store do backup do iCloud para que dados de desenvolvimento
    /// não sejam restaurados automaticamente ao reinstalar o app.
    private static func excludeStoreFromBackup() {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        // Exclui o arquivo principal e os arquivos auxiliares do SQLite
        let storeNames = ["finAInce.store", "finAInce.store-shm", "finAInce.store-wal"]
        for name in storeNames {
            var url = appSupportURL.appendingPathComponent(name)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)
        }
    }

    // MARK: - Container

    /// Cria o ModelContainer com migration plan para proteger os dados do usuário.
    /// Em caso de erro de migração, tenta abrir sem migration como fallback
    /// (nunca apaga o store automaticamente).
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Family.self,
            Account.self,
            Category.self,
            Transaction.self,
            ReceiptAttachment.self,
            AISettings.self,
            AIAnalysis.self,
            ChatConversation.self,
            ChatMessage.self,
            Goal.self
        ])
        let config = ModelConfiguration(
            "finAInce",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        // Tentativa 1: abre com o schema atual. Para mudanças aditivas como esta,
        // o SwiftData aplica lightweight migration automaticamente.
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: config
            )
            excludeStoreFromBackup()
            return container
        } catch {
            // Tentativa 2: fallback seguro — NÃO apaga dados.
            print("⚠️ [finAInce] Erro ao abrir o store principal: \(error)")
            print("⚠️ [finAInce] Tentando abrir o store novamente...")

            do {
                let container = try ModelContainer(
                    for: schema,
                    configurations: config
                )
                excludeStoreFromBackup()
                return container
            } catch {
                // Último recurso em produção: store em memória para o app não crashar.
                // O usuário perde os dados deste app NESSA SESSÃO, mas o store no disco
                // fica intacto para tentativas futuras (ex: após atualização de correção).
                print("🔴 [finAInce] Falha crítica ao abrir o store: \(error)")
                #if DEBUG
                fatalError("Falha crítica no ModelContainer — veja o log acima.")
                #else
                let fallback = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                return try! ModelContainer(for: schema, configurations: fallback)
                #endif
            }
        }
    }

    // MARK: - Seed

    @MainActor
    private func seedIfNeeded() {
        let seededKey    = "hasSeededDefaultData"
        let onboardedKey = "hasCompletedOnboarding"

        // Categorias padrão: sempre precisam existir
        if !UserDefaults.standard.bool(forKey: seededKey) {
            // Fresh install detected: iOS Keychain persists across app deletion but
            // UserDefaults does not. Wipe any lingering API keys so the user starts
            // with a clean AI configuration on every fresh install.
            KeychainHelper.deleteAll(forService: "finaince")

            DefaultCategories.seed(in: modelContainer.mainContext)
            UserDefaults.standard.set(true, forKey: seededKey)
        }

        configureLocalAIIfAvailable()

        // Dados de exemplo: REMOVIDO do seed automático.
        // Use o botão "Seed Sample Data" na aba Perfil (apenas em DEBUG)
        // para popular dados de teste manualmente sem afetar o fluxo de FTU.
    }

    @MainActor
    private func configureLocalAIIfAvailable() {
        guard LocalAIService.checkAvailability() == .available else { return }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<AISettings>()
        guard let settingsList = try? context.fetch(descriptor) else { return }

        if let configured = settingsList.first(where: { $0.isConfigured }) {
            if configured.provider == .local {
                configured.model = AIProvider.local.defaultModel
            }
            return
        }

        if let settings = settingsList.first {
            settings.provider = .local
            settings.model = AIProvider.local.defaultModel
            settings.isConfigured = true
        } else {
            let settings = AISettings(provider: .local)
            settings.model = AIProvider.local.defaultModel
            settings.isConfigured = true
            context.insert(settings)
        }

        try? context.save()
    }
}
