import SwiftUI
import SwiftData

@main
struct FamilyFinanceApp: App {
    let modelContainer: ModelContainer

    private static let migrationKey = "hasCompletedStorePathMigration"
    private static let cloudPreparationKey = "hasPreparedCloudMigration.v2"
    private static let needsCloudImportKey = "needsLocalToCloudImport.v2"
    private static let needsCloudDeduplicationKey = "needsCloudDeduplication"

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

    // MARK: - Container

    /// Cria o ModelContainer.
    ///
    /// • Usuário FREE  → store local SQLite (sem backup automático via iCloud).
    /// • Usuário CLOUD → store com CloudKit private database, sync em tempo real
    ///                   entre dispositivos e backup automático.
    ///
    /// A escolha é feita no launch com base em `EntitlementManager.isCloudEnabled`.
    /// Após a compra o usuário reinicia o app para ativar o CloudKit.
    private static func makeContainer() -> ModelContainer {
        let schema = makeSchema()

        // ── Escolhe a configuração com base no entitlement ────────────────
        let cloudEnabled = EntitlementManager.shared.isCloudEnabled

        // CloudKit usa um arquivo separado para evitar conflito com o store local.
        // Isso garante que o store local nunca é corrompido se o CloudKit falhar.
        //
        // IMPORTANTE: usamos URL explícita + cloudKitDatabase: .none para o store local.
        // Sem isso, ModelConfiguration(.automatic) redireciona o arquivo para o AppGroup
        // container e aplica validação CloudKit, o que quebra schemas não-opcionais.
        let localStoreURL = localStoreURL()

        // ── Migração do store antigo (AppGroup → container privado) ──────────
        // Antes desta versão, ModelConfiguration sem URL + cloudKitDatabase:.automatic
        // redirecionava o SQLite para o AppGroup container. Usamos uma flag de
        // UserDefaults para garantir que a migração rode exatamente uma vez —
        // mesmo que o novo path já exista (pode ser um store vazio de uma tentativa
        // anterior com falha).
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            Self.migrateAppGroupStoreIfNeeded(to: localStoreURL)
            UserDefaults.standard.set(true, forKey: migrationKey)
        }

        let localConfig = ModelConfiguration(
            schema: schema,
            url: localStoreURL,
            cloudKitDatabase: .none
        )

        // ── Tenta CloudKit ────────────────────────────────────────────────
        if cloudEnabled {
            let cloudStoreURL = cloudStoreURL()

            // Primeira ativação do Cloud nesta instalação:
            // remove o store cloud local antigo para evitar re-upload de dados
            // obsoletos e agenda uma importação controlada a partir do store local.
            if !UserDefaults.standard.bool(forKey: cloudPreparationKey) {
                removeStoreFiles(at: cloudStoreURL)
                let needsImport = storeExists(at: localStoreURL)
                UserDefaults.standard.set(needsImport, forKey: needsCloudImportKey)
                UserDefaults.standard.set(true, forKey: needsCloudDeduplicationKey)
                UserDefaults.standard.set(true, forKey: cloudPreparationKey)
            }

            let cloudConfig = ModelConfiguration(
                schema: schema,
                url: cloudStoreURL,
                cloudKitDatabase: .private("iCloud.Moura.finaince")
            )
            do {
                let container = try ModelContainer(
                    for: schema,
                    configurations: cloudConfig
                )
                print("☁️ [finAInce] Container: CloudKit ativo")
                return container
            } catch {
                // CloudKit indisponível (iCloud deslogado, container novo, sem rede…)
                // Cai silenciosamente para o store local — dados não são perdidos.
                print("⚠️ [finAInce] CloudKit indisponível, usando store local: \(error)")
            }
        }

        // ── Store local ───────────────────────────────────────────────────
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: localConfig
            )
            print("💾 [finAInce] Container: local")
            return container
        } catch {
            // Último recurso: store em memória (nunca apaga dados do disco).
            print("🔴 [finAInce] Falha crítica ao abrir o store local: \(error)")
            #if DEBUG
            fatalError("Falha crítica no ModelContainer — veja o log acima.")
            #else
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: fallback)
            #endif
        }
    }

    // MARK: - Store paths

    private static func makeSchema() -> Schema {
        Schema([
            Family.self,
            Account.self,
            Category.self,
            Transaction.self,
            ReceiptAttachment.self,
            AISettings.self,
            AIAnalysis.self,
            ChatConversation.self,
            ChatMessage.self,
            Goal.self,
            CostCenter.self,
            CostCenterFile.self
        ])
    }

    private static func storeURL(fileName: String) -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )
        return appSupport.appendingPathComponent(fileName)
    }

    private static func localStoreURL() -> URL {
        storeURL(fileName: "finAInce.store")
    }

    private static func cloudStoreURL() -> URL {
        storeURL(fileName: "finAInce-cloud.store")
    }

    private static func storeExists(at url: URL) -> Bool {
        let fm = FileManager.default
        return ["", "-wal", "-shm"].contains { suffix in
            fm.fileExists(atPath: url.path + suffix)
        }
    }

    private static func removeStoreFiles(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let fileURL = URL(fileURLWithPath: url.path + suffix)
            if fm.fileExists(atPath: fileURL.path) {
                try? fm.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - Store migration (AppGroup → private container)

    /// Copia o SQLite do AppGroup container (localização anterior) para o container
    /// privado do app (nova localização com cloudKitDatabase: .none).
    /// Copia os três arquivos do SQLite WAL journal (.store, .store-shm, .store-wal).
    /// Chamado apenas quando o arquivo de destino ainda não existe.
    private static func migrateAppGroupStoreIfNeeded(to destination: URL) {
        guard let groupContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.Moura.finaince"
        ) else {
            print("💾 [finAInce] AppGroup não acessível — nenhum dado a migrar")
            return
        }

        let oldURL = groupContainer
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("finAInce.store")

        guard FileManager.default.fileExists(atPath: oldURL.path) else {
            print("💾 [finAInce] Store antigo não encontrado no AppGroup — instalação limpa")
            return
        }

        // SQLite WAL mode gera até 3 arquivos: .store / .store-shm / .store-wal
        let fm = FileManager.default
        var copied = 0
        for suffix in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: oldURL.path + suffix)
            let dst = URL(fileURLWithPath: destination.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            // Remove destino (pode ser um store vazio de tentativa anterior com falha)
            try? fm.removeItem(at: dst)
            do {
                try fm.copyItem(at: src, to: dst)
                copied += 1
            } catch {
                print("⚠️ [finAInce] Erro ao copiar \(src.lastPathComponent): \(error)")
            }
        }

        if copied > 0 {
            print("✅ [finAInce] Store migrado do AppGroup (\(copied) arquivo(s))")
        }
    }

    // MARK: - Seed

    @MainActor
    private func seedIfNeeded() {
        let needsCloudImport = UserDefaults.standard.bool(forKey: Self.needsCloudImportKey)

        if needsCloudImport {
            Task {
                try? await Task.sleep(for: .seconds(5))
                importLocalStoreIntoCloudIfNeeded()
                ensurePrimaryFamilyIfNeeded()
                deduplicateCloudDataIfNeeded()
                ensureDefaultDataIfNeeded()
                configureLocalAIIfAvailable()
            }
            return
        }

        ensureDefaultDataIfNeeded()
        ensurePrimaryFamilyIfNeeded()
        configureLocalAIIfAvailable()
        Task {
            try? await Task.sleep(for: .seconds(5))
            deduplicateCloudDataIfNeeded()
        }

        // Dados de exemplo: REMOVIDO do seed automático.
        // Use o botão "Seed Sample Data" na aba Perfil (apenas em DEBUG)
        // para popular dados de teste manualmente sem afetar o fluxo de FTU.
    }

    @MainActor
    private func ensureDefaultDataIfNeeded() {
        let context = modelContainer.mainContext
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let hasSystemCategories = categories.contains { $0.isSystem }

        if !hasSystemCategories {
            // Fresh install detected: iOS Keychain persists across app deletion but
            // UserDefaults does not. Wipe any lingering API keys so the user starts
            // with a clean AI configuration on every fresh install.
            if categories.isEmpty {
                KeychainHelper.deleteAll(forService: "finaince")
            }

            DefaultCategories.seed(in: context)
        }

        UserDefaults.standard.set(true, forKey: "hasSeededDefaultData")
    }

    @MainActor
    private func ensurePrimaryFamilyIfNeeded() {
        let context = modelContainer.mainContext
        let families = ((try? context.fetch(FetchDescriptor<Family>())) ?? [])
            .sorted(by: { $0.createdAt < $1.createdAt })

        if let primaryFamily = families.first {
            if families.count > 1 {
                mergeDuplicateFamilies(in: context, primaryFamily: primaryFamily, duplicates: Array(families.dropFirst()))
            }

            backfillOrphanedRecords(in: context, primaryFamily: primaryFamily)
            return
        }

        let hasUserData =
            ((try? context.fetchCount(FetchDescriptor<Account>())) ?? 0) > 0 ||
            ((try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0) > 0 ||
            ((try? context.fetchCount(FetchDescriptor<Goal>())) ?? 0) > 0 ||
            ((try? context.fetchCount(FetchDescriptor<AISettings>())) ?? 0) > 0 ||
            ((try? context.fetchCount(FetchDescriptor<AIAnalysis>())) ?? 0) > 0 ||
            ((try? context.fetchCount(FetchDescriptor<ChatConversation>())) ?? 0) > 0

        guard hasUserData else { return }

        let cloudEnabled = EntitlementManager.shared.isCloudEnabled
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if cloudEnabled && !hasCompletedOnboarding {
            print("☁️ [finAInce] Aguardando sync inicial antes de criar Family principal")
            return
        }

        let primaryFamily = Family(name: primaryFamilyName())
        context.insert(primaryFamily)
        backfillOrphanedRecords(in: context, primaryFamily: primaryFamily)
    }

    @MainActor
    private func backfillOrphanedRecords(in context: ModelContext, primaryFamily: Family) {
        var didChange = false

        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        for account in accounts where account.family == nil {
            account.family = primaryFamily
            didChange = true
        }

        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        for transaction in transactions where transaction.family == nil {
            transaction.family = primaryFamily
            didChange = true
        }

        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        for goal in goals where goal.family == nil {
            goal.family = primaryFamily
            didChange = true
        }

        let analyses = (try? context.fetch(FetchDescriptor<AIAnalysis>())) ?? []
        for analysis in analyses where analysis.family == nil {
            analysis.family = primaryFamily
            didChange = true
        }

        let conversations = (try? context.fetch(FetchDescriptor<ChatConversation>())) ?? []
        for conversation in conversations where conversation.family == nil {
            conversation.family = primaryFamily
            didChange = true
        }

        guard didChange else { return }

        do {
            try context.save()
            print("✅ [finAInce] Family principal garantida e vínculos órfãos corrigidos")
        } catch {
            print("⚠️ [finAInce] Erro ao garantir Family principal: \(error)")
        }
    }

    @MainActor
    private func mergeDuplicateFamilies(in context: ModelContext, primaryFamily: Family, duplicates: [Family]) {
        var didChange = false

        for duplicate in duplicates {
            (duplicate.accounts ?? []).forEach { $0.family = primaryFamily }
            (duplicate.categories ?? []).forEach { $0.family = primaryFamily }
            (duplicate.transactions ?? []).forEach { $0.family = primaryFamily }
            (duplicate.analyses ?? []).forEach { $0.family = primaryFamily }
            (duplicate.conversations ?? []).forEach { $0.family = primaryFamily }
            (duplicate.goals ?? []).forEach { $0.family = primaryFamily }
            context.delete(duplicate)
            didChange = true
        }

        guard didChange else { return }

        do {
            try context.save()
            print("✅ [finAInce] Families duplicadas unificadas")
        } catch {
            print("⚠️ [finAInce] Erro ao unificar Families duplicadas: \(error)")
        }
    }

    private func primaryFamilyName() -> String {
        let storedName = UserDefaults.standard.string(forKey: "user.name")?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let storedName, !storedName.isEmpty {
            return storedName
        }

        return "Minha família"
    }

    // MARK: - Local → Cloud import

    @MainActor
    private func importLocalStoreIntoCloudIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.needsCloudImportKey) else { return }
        defer { UserDefaults.standard.set(false, forKey: Self.needsCloudImportKey) }

        let localStoreURL = Self.localStoreURL()
        guard Self.storeExists(at: localStoreURL) else {
            print("☁️ [finAInce] Sem store local para importar")
            return
        }

        let cloudContext = modelContainer.mainContext
        guard isCloudStoreEffectivelyEmpty(context: cloudContext) else {
            print("☁️ [finAInce] Cloud já contém dados; importação local ignorada")
            return
        }

        let schema = Self.makeSchema()
        let localConfig = ModelConfiguration(
            schema: schema,
            url: localStoreURL,
            cloudKitDatabase: .none
        )

        let localContainer: ModelContainer
        do {
            localContainer = try ModelContainer(for: schema, configurations: localConfig)
        } catch {
            print("⚠️ [finAInce] Falha ao abrir store local para importação: \(error)")
            return
        }

        let localContext = localContainer.mainContext

        let localFamilies = (try? localContext.fetch(FetchDescriptor<Family>())) ?? []
        let localAccounts = (try? localContext.fetch(FetchDescriptor<Account>())) ?? []
        let localCategories = (try? localContext.fetch(FetchDescriptor<Category>())) ?? []
        let localGoals = (try? localContext.fetch(FetchDescriptor<Goal>())) ?? []
        let localSettings = (try? localContext.fetch(FetchDescriptor<AISettings>())) ?? []
        let localAnalyses = (try? localContext.fetch(FetchDescriptor<AIAnalysis>())) ?? []
        let localConversations = (try? localContext.fetch(FetchDescriptor<ChatConversation>())) ?? []
        let localMessages = (try? localContext.fetch(FetchDescriptor<ChatMessage>())) ?? []
        let localTransactions = (try? localContext.fetch(FetchDescriptor<Transaction>())) ?? []
        let localAttachments = (try? localContext.fetch(FetchDescriptor<ReceiptAttachment>())) ?? []

        let hasAnyLocalData = !localFamilies.isEmpty
            || !localAccounts.isEmpty
            || !localCategories.isEmpty
            || !localGoals.isEmpty
            || !localSettings.isEmpty
            || !localAnalyses.isEmpty
            || !localConversations.isEmpty
            || !localMessages.isEmpty
            || !localTransactions.isEmpty
            || !localAttachments.isEmpty

        guard hasAnyLocalData else {
            print("☁️ [finAInce] Store local vazio; nada para migrar")
            return
        }

        var familyMap: [UUID: Family] = [:]
        for family in localFamilies.sorted(by: { $0.createdAt < $1.createdAt }) {
            let copy = Family(name: family.name)
            copy.id = family.id
            copy.createdAt = family.createdAt
            cloudContext.insert(copy)
            familyMap[family.id] = copy
        }

        var categoryMap: [UUID: Category] = [:]
        let rootCategories = localCategories
            .filter { $0.parent == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        for category in rootCategories {
            let copy = cloneCategory(category, parent: nil, familyMap: familyMap)
            cloudContext.insert(copy)
            categoryMap[category.id] = copy
        }

        let subcategories = localCategories
            .filter { $0.parent != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        for category in subcategories {
            guard let parentID = category.parent?.id else { continue }
            let copy = cloneCategory(
                category,
                parent: categoryMap[parentID],
                familyMap: familyMap
            )
            cloudContext.insert(copy)
            categoryMap[category.id] = copy
        }

        var accountMap: [UUID: Account] = [:]
        for account in localAccounts.sorted(by: { $0.createdAt < $1.createdAt }) {
            let copy = Account(
                name: account.name,
                type: account.type,
                balance: account.balance,
                icon: account.icon,
                color: account.color,
                isDefault: account.isDefault,
                ccBillingStartDay: account.ccBillingStartDay,
                ccBillingEndDay: account.ccBillingEndDay
            )
            copy.id = account.id
            copy.createdAt = account.createdAt
            copy.family = account.family.flatMap { familyMap[$0.id] }
            cloudContext.insert(copy)
            accountMap[account.id] = copy
        }

        var transactionMap: [UUID: Transaction] = [:]
        for transaction in localTransactions.sorted(by: { $0.createdAt < $1.createdAt }) {
            let copy = Transaction(
                type: transaction.type,
                amount: transaction.amount,
                date: transaction.date,
                placeName: transaction.placeName,
                placeGoogleId: transaction.placeGoogleId,
                notes: transaction.notes,
                recurrenceType: transaction.recurrenceType,
                installmentIndex: transaction.installmentIndex,
                installmentTotal: transaction.installmentTotal,
                installmentGroupId: transaction.installmentGroupId,
                isPaid: transaction.isPaid
            )
            copy.id = transaction.id
            copy.createdAt = transaction.createdAt
            copy.importHash = transaction.importHash
            copy.family = transaction.family.flatMap { familyMap[$0.id] }
            copy.account = transaction.account.flatMap { accountMap[$0.id] }
            copy.category = transaction.category.flatMap { categoryMap[$0.id] }
            copy.subcategory = transaction.subcategory.flatMap { categoryMap[$0.id] }
            copy.destinationAccount = transaction.destinationAccount.flatMap { accountMap[$0.id] }
            cloudContext.insert(copy)
            transactionMap[transaction.id] = copy
        }

        for goal in localGoals.sorted(by: { $0.createdAt < $1.createdAt }) {
            let copy = Goal(
                title: goal.title,
                targetAmount: goal.targetAmount,
                period: goal.period,
                emoji: goal.emoji,
                category: goal.category.flatMap { categoryMap[$0.id] }
            )
            copy.id = goal.id
            copy.createdAt = goal.createdAt
            copy.isActive = goal.isActive
            copy.family = goal.family.flatMap { familyMap[$0.id] }
            cloudContext.insert(copy)
        }

        for settings in localSettings {
            let copy = AISettings(provider: settings.provider)
            copy.id = settings.id
            copy.model = settings.model
            copy.isConfigured = settings.isConfigured
            copy.family = settings.family.flatMap { familyMap[$0.id] }
            cloudContext.insert(copy)
        }

        for analysis in localAnalyses.sorted(by: { $0.generatedAt < $1.generatedAt }) {
            let copy = AIAnalysis(
                monthRef: analysis.monthRef,
                provider: analysis.provider,
                type: analysis.type,
                content: analysis.content
            )
            copy.id = analysis.id
            copy.generatedAt = analysis.generatedAt
            copy.family = analysis.family.flatMap { familyMap[$0.id] }
            cloudContext.insert(copy)
        }

        var conversationMap: [UUID: ChatConversation] = [:]
        for conversation in localConversations.sorted(by: { $0.createdAt < $1.createdAt }) {
            let copy = ChatConversation(title: conversation.title, monthRef: conversation.monthRef)
            copy.id = conversation.id
            copy.createdAt = conversation.createdAt
            copy.family = conversation.family.flatMap { familyMap[$0.id] }
            cloudContext.insert(copy)
            conversationMap[conversation.id] = copy
        }

        for message in localMessages.sorted(by: { $0.timestamp < $1.timestamp }) {
            let copy = ChatMessage(role: message.role, content: message.content)
            copy.id = message.id
            copy.timestamp = message.timestamp
            copy.conversation = message.conversation.flatMap { conversationMap[$0.id] }
            cloudContext.insert(copy)
        }

        for attachment in localAttachments.sorted(by: { $0.createdAt < $1.createdAt }) {
            let copy = ReceiptAttachment(
                fileName: attachment.fileName,
                storedFileName: attachment.storedFileName,
                contentType: attachment.contentType,
                kind: attachment.kind
            )
            copy.id = attachment.id
            copy.createdAt = attachment.createdAt
            copy.transaction = attachment.transaction.flatMap { transactionMap[$0.id] }
            cloudContext.insert(copy)
        }

        do {
            try cloudContext.save()
            UserDefaults.standard.set(true, forKey: Self.needsCloudDeduplicationKey)
            print("✅ [finAInce] Migração local → Cloud concluída")
        } catch {
            print("⚠️ [finAInce] Falha ao salvar migração local → Cloud: \(error)")
        }
    }

    @MainActor
    private func isCloudStoreEffectivelyEmpty(context: ModelContext) -> Bool {
        let familyCount = (try? context.fetchCount(FetchDescriptor<Family>())) ?? 0
        let accountCount = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        let transactionCount = (try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0
        let goalCount = (try? context.fetchCount(FetchDescriptor<Goal>())) ?? 0
        let conversationCount = (try? context.fetchCount(FetchDescriptor<ChatConversation>())) ?? 0
        let analysisCount = (try? context.fetchCount(FetchDescriptor<AIAnalysis>())) ?? 0
        let categoryCount = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0

        return familyCount == 0
            && accountCount == 0
            && transactionCount == 0
            && goalCount == 0
            && conversationCount == 0
            && analysisCount == 0
            && categoryCount == 0
    }

    @MainActor
    private func cloneCategory(
        _ category: Category,
        parent: Category?,
        familyMap: [UUID: Family]
    ) -> Category {
        let copy = Category(
            name: category.name,
            systemKey: category.systemKey,
            icon: category.icon,
            color: category.color,
            type: category.type,
            isSystem: category.isSystem,
            sortOrder: category.sortOrder,
            parent: parent
        )
        copy.id = category.id
        copy.family = category.family.flatMap { familyMap[$0.id] }
        return copy
    }

    // MARK: - Cloud Deduplication

    /// Remove registros duplicados que o CloudKit pode criar durante o sync inicial.
    /// Roda uma única vez após a primeira ativação do Cloud, com delay de 5s para
    /// deixar o sync inicial terminar antes de tentar limpar.
    @MainActor
    private func deduplicateCloudDataIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.needsCloudDeduplicationKey) else { return }
        deduplicateCloudData()
        UserDefaults.standard.set(false, forKey: Self.needsCloudDeduplicationKey)
    }

    @MainActor
    private func deduplicateCloudData() {
        let context = modelContainer.mainContext
        print("🔁 [finAInce] Iniciando deduplicação pós-CloudKit...")

        // ── Family ────────────────────────────────────────────────────────
        // Mantém apenas uma Family, remove as duplicatas
        if let families = try? context.fetch(FetchDescriptor<Family>()),
           families.count > 1 {
            let keep = families.first!
            for dup in families.dropFirst() {
                // Reatribui contas e categorias para a família que vai ficar
                (dup.accounts ?? []).forEach { $0.family = keep }
                context.delete(dup)
            }
            print("🔁 [finAInce] Family: removidas \(families.count - 1) duplicatas")
        }

        // ── Category ──────────────────────────────────────────────────────
        // Agrupa por systemKey (categorias do sistema) ou por name+parent (custom)
        if let categories = try? context.fetch(FetchDescriptor<Category>()) {
            var seen: [String: Category] = [:]
            for cat in categories {
                let dedupeKey: String
                if let key = cat.systemKey, !key.isEmpty {
                    let parentKey = cat.parent?.systemKey ?? "_root"
                    dedupeKey = "\(parentKey)/\(key)"
                } else {
                    let parentName = cat.parent?.name ?? "_root"
                    dedupeKey = "\(parentName)/\(cat.name)"
                }

                if let existing = seen[dedupeKey] {
                    // Reatribui transações para a categoria que vai ficar
                    (cat.transactions ?? []).forEach { $0.category = existing }
                    (cat.subcategoryTransactions ?? []).forEach { $0.subcategory = existing }
                    context.delete(cat)
                } else {
                    seen[dedupeKey] = cat
                }
            }
            let removed = categories.count - seen.count
            if removed > 0 {
                print("🔁 [finAInce] Category: removidas \(removed) duplicatas")
            }
        }

        // ── Account ───────────────────────────────────────────────────────
        // Agrupa por name+type
        if let accounts = try? context.fetch(FetchDescriptor<Account>()) {
            var seen: [String: Account] = [:]
            for acc in accounts {
                let dedupeKey = "\(acc.name)/\(acc.type.rawValue)"
                if let existing = seen[dedupeKey] {
                    // Reatribui transações para a conta que vai ficar
                    (acc.transactions ?? []).forEach { $0.account = existing }
                    (acc.outgoingTransfers ?? []).forEach { $0.destinationAccount = existing }
                    context.delete(acc)
                } else {
                    seen[dedupeKey] = acc
                }
            }
            let removed = accounts.count - seen.count
            if removed > 0 {
                print("🔁 [finAInce] Account: removidas \(removed) duplicatas")
            }
        }

        // ── Goal ──────────────────────────────────────────────────────────
        if let goals = try? context.fetch(FetchDescriptor<Goal>()) {
            var seen: [String: Goal] = [:]
            for goal in goals {
                let categoryKey = goal.category?.id.uuidString ?? "_all"
                let dedupeKey = [
                    goal.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    String(goal.targetAmount),
                    goal.period.rawValue,
                    categoryKey
                ].joined(separator: "|")

                if let existing = seen[dedupeKey] {
                    if existing.createdAt <= goal.createdAt {
                        context.delete(goal)
                    } else {
                        context.delete(existing)
                        seen[dedupeKey] = goal
                    }
                } else {
                    seen[dedupeKey] = goal
                }
            }
        }

        // ── Transaction ───────────────────────────────────────────────────
        if let transactions = try? context.fetch(FetchDescriptor<Transaction>()) {
            var seen: [String: Transaction] = [:]
            for transaction in transactions.sorted(by: { $0.createdAt < $1.createdAt }) {
                let dedupeKey = transactionDeduplicationKey(for: transaction)
                if let existing = seen[dedupeKey] {
                    mergeAttachments(from: transaction, into: existing)
                    context.delete(transaction)
                } else {
                    seen[dedupeKey] = transaction
                }
            }
        }

        // ── AI Settings ────────────────────────────────────────────────────
        if let settingsList = try? context.fetch(FetchDescriptor<AISettings>()) {
            var seen: [String: AISettings] = [:]
            for settings in settingsList {
                let dedupeKey = settings.provider.rawValue
                if let existing = seen[dedupeKey] {
                    if existing.isConfigured {
                        context.delete(settings)
                    } else {
                        context.delete(existing)
                        seen[dedupeKey] = settings
                    }
                } else {
                    seen[dedupeKey] = settings
                }
            }
        }

        do {
            try context.save()
            print("✅ [finAInce] Deduplicação concluída")
        } catch {
            print("⚠️ [finAInce] Erro ao salvar após deduplicação: \(error)")
        }
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

        guard settingsList.isEmpty else { return }

        let settings = AISettings(provider: .local)
        settings.model = AIProvider.local.defaultModel
        settings.isConfigured = true
        context.insert(settings)

        try? context.save()
    }

    @MainActor
    private func transactionDeduplicationKey(for transaction: Transaction) -> String {
        if let importHash = transaction.importHash, !importHash.isEmpty {
            return "import|\(importHash)"
        }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: transaction.date).timeIntervalSince1970
        let amount = String(format: "%.2f", transaction.amount)
        let merchant = (transaction.placeName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let notes = (transaction.notes ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let accountID = transaction.account?.id.uuidString ?? "_"
        let categoryID = transaction.category?.id.uuidString ?? "_"
        let subcategoryID = transaction.subcategory?.id.uuidString ?? "_"
        let destinationID = transaction.destinationAccount?.id.uuidString ?? "_"
        let installmentGroupID = transaction.installmentGroupId?.uuidString ?? "_"

        return [
            transaction.type.rawValue,
            amount,
            String(Int(day)),
            merchant,
            notes,
            accountID,
            categoryID,
            subcategoryID,
            destinationID,
            transaction.recurrenceType.rawValue,
            transaction.installmentIndex.map(String.init) ?? "_",
            transaction.installmentTotal.map(String.init) ?? "_",
            installmentGroupID,
            transaction.isPaid ? "1" : "0"
        ].joined(separator: "|")
    }

    @MainActor
    private func mergeAttachments(from duplicate: Transaction, into existing: Transaction) {
        for attachment in duplicate.receiptAttachments ?? [] {
            attachment.transaction = existing
        }
    }

    #if DEBUG
    struct DebugCloudStatus {
        let cloudEntitlementEnabled: Bool
        let preparedCloudMigration: Bool
        let needsCloudImport: Bool
        let needsCloudDeduplication: Bool
        let localStoreExists: Bool
        let cloudStoreExists: Bool
    }

    static func debugCloudStatus() -> DebugCloudStatus {
        DebugCloudStatus(
            cloudEntitlementEnabled: EntitlementManager.shared.isCloudEnabled,
            preparedCloudMigration: UserDefaults.standard.bool(forKey: cloudPreparationKey),
            needsCloudImport: UserDefaults.standard.bool(forKey: needsCloudImportKey),
            needsCloudDeduplication: UserDefaults.standard.bool(forKey: needsCloudDeduplicationKey),
            localStoreExists: storeExists(at: localStoreURL()),
            cloudStoreExists: storeExists(at: cloudStoreURL())
        )
    }

    static func debugResetPersistentStores() {
        removeStoreFiles(at: localStoreURL())
        removeStoreFiles(at: cloudStoreURL())
        UserDefaults.standard.removeObject(forKey: cloudPreparationKey)
        UserDefaults.standard.removeObject(forKey: needsCloudImportKey)
        UserDefaults.standard.removeObject(forKey: needsCloudDeduplicationKey)
    }
    #endif
}
