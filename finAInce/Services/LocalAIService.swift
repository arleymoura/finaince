// LocalAIService.swift
// IA on-device via Apple Intelligence (FoundationModels · iOS 26+)
// Compila em qualquer target — todo o código runtime está protegido por
// #if canImport(FoundationModels) + #available(iOS 26, *)

import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

fileprivate func financeNormalizeForMatching(_ text: String) -> String {
    text
        .lowercased()
        .replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
        .folding(options: [.diacriticInsensitive], locale: .current)
}

// MARK: - Thread-safe snapshots (plain Sendable structs, sem SwiftData)

struct TransactionSnapshot: Sendable {
    let id: UUID
    let amount: Double
    let typeRaw: String          // "expense" | "transfer"
    let categorySystemKey: String?
    let rootCategorySystemKey: String?
    let categoryName: String
    let subcategoryName: String?
    let categoryIcon: String
    let categoryColor: String
    let accountName: String
    let date: Date
    let notes: String?
    let placeName: String?

    var isExpense: Bool { typeRaw == "expense" }
}

struct GoalSnapshot: Sendable {
    let title: String
    let emoji: String
    let targetAmount: Double
    let categoryName: String?    // nil = todos os gastos
    let monthlySpend: Double     // gasto do mês atual para essa categoria/geral
}

extension GoalSnapshot {
    var percentUsed: Double {
        guard targetAmount > 0 else { return 0 }
        return (monthlySpend / targetAmount) * 100
    }
    var isNearLimit: Bool { percentUsed >= 80 && percentUsed < 100 }
    var isOverLimit: Bool { percentUsed >= 100 }
}

struct AccountSnapshot: Sendable {
    let name: String
    let typeLabel: String
    let semanticType: String
    let aliases: [String]
    let balance: Double
    let isDefault: Bool
    let creditLimit: Double?
    let billingClosingDay: Int?
    let paymentDueDay: Int?
    let estimatedBillAmount: Double?
    let billingWindowStart: Date?
    let billingWindowEnd: Date?
    let daysUntilClosing: Int?
}

struct ProjectSnapshot: Sendable {
    let name: String
    let description: String?
    let isActive: Bool
    let budget: Double?
    let spent: Double
}

struct FamilySnapshot: Sendable {
    let name: String
    let accountsCount: Int
    let goalsCount: Int
}

struct UserProfileSnapshot: Sendable {
    let name: String
    let adultsCount: Int
    let childrenCount: Int
}

struct RegisteredCategorySnapshot: Sendable {
    let systemKey: String?
    let displayName: String

    init(systemKey: String?, displayName: String) {
        self.systemKey = systemKey
        self.displayName = displayName
    }
}

// MARK: - SwiftData → Snapshot helpers

extension Transaction {
    func asSnapshot() -> TransactionSnapshot {
        let rootCategory = category?.rootCategory
        return TransactionSnapshot(
            id:              id,
            amount:          amount,
            typeRaw:         type.rawValue,
            categorySystemKey: category?.systemKey,
            rootCategorySystemKey: category?.rootSystemKey,
            categoryName:    category?.displayName ?? "Sem categoria",
            subcategoryName: subcategory?.displayName,
            categoryIcon:    rootCategory?.icon ?? category?.icon ?? "tag.fill",
            categoryColor:   rootCategory?.color ?? category?.color ?? "#8E8E93",
            accountName:     account?.name     ?? "Sem conta",
            date:            date,
            notes:           notes,
            placeName:       placeName
        )
    }
}

extension Goal {
    /// monthTx = transações de despesa do mês atual (pré-filtradas pelo caller)
    func asSnapshot(monthExpenses: [Transaction]) -> GoalSnapshot {
        let spend: Double
        if let cat = category {
            spend = monthExpenses
                .filter { $0.category?.persistentModelID == cat.persistentModelID }
                .reduce(0) { $0 + $1.amount }
        } else {
            spend = monthExpenses.reduce(0) { $0 + $1.amount }
        }
        return GoalSnapshot(
            title:        title,
            emoji:        emoji,
            targetAmount: targetAmount,
            categoryName: category?.displayName,
            monthlySpend: spend
        )
    }
}

extension Account {
    func asSnapshot(transactions: [Transaction], referenceDate: Date = Date()) -> AccountSnapshot {
        let forecast = Self.creditCardForecast(for: self, transactions: transactions, referenceDate: referenceDate)
        return AccountSnapshot(
            name:      name,
            typeLabel: type.label,
            semanticType: Self.semanticType(for: type),
            aliases: Self.aliases(for: type),
            balance:   balance,
            isDefault: isDefault,
            creditLimit: ccCreditLimit,
            billingClosingDay: billingClosingDay,
            paymentDueDay: ccPaymentDueDay,
            estimatedBillAmount: forecast?.amount,
            billingWindowStart: forecast?.start,
            billingWindowEnd: forecast?.end,
            daysUntilClosing: forecast?.daysUntilClosing
        )
    }

    private static func semanticType(for type: AccountType) -> String {
        switch type {
        case .checking:
            return "bank_checking_account"
        case .cash:
            return "cash_wallet_account"
        case .creditCard:
            return "credit_card_account"
        }
    }

    private static func aliases(for type: AccountType) -> [String] {
        switch type {
        case .checking:
            return ["checking", "bank", "current account", "conta corrente"]
        case .cash:
            return ["cash", "wallet", "money", "carteira", "dinheiro"]
        case .creditCard:
            return ["credit card", "card", "invoice", "fatura", "cartao de credito"]
        }
    }

    private static func creditCardForecast(
        for account: Account,
        transactions: [Transaction],
        referenceDate: Date
    ) -> (amount: Double, start: Date, end: Date, daysUntilClosing: Int)? {
        guard account.type == .creditCard,
              let cycle = account.billingCycleRange(containing: referenceDate) else {
            return nil
        }

        let calendar = Calendar.current
        let amount = transactions
            .filter { $0.type == .expense }
            .filter { $0.account?.id == account.id }
            .filter { $0.date >= cycle.start && $0.date < cycle.nextStart }
            .reduce(0) { $0 + $1.amount }

        let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: referenceDate), to: cycle.nextStart).day ?? 0)
        return (amount: amount, start: cycle.start, end: cycle.end, daysUntilClosing: days)
    }
}

extension CostCenter {
    func asSnapshot(currencyCode: String, transactions: [Transaction]) -> ProjectSnapshot {
        let spent = transactions
            .filter { $0.costCenterId == id }
            .reduce(0) { $0 + $1.amount }
        return ProjectSnapshot(
            name: name,
            description: desc,
            isActive: isActive,
            budget: budget,
            spent: spent
        )
    }
}

extension Family {
    func asSnapshot() -> FamilySnapshot {
        FamilySnapshot(
            name: name,
            accountsCount: accounts?.count ?? 0,
            goalsCount: goals?.count ?? 0
        )
    }
}

// MARK: - FinanceContext (pacote completo enviado ao modelo)

struct FinanceContext: Sendable {
    let transactions:       [TransactionSnapshot]
    let goals:              [GoalSnapshot]
    let accounts:           [AccountSnapshot]
    let projects:           [ProjectSnapshot]
    let families:           [FamilySnapshot]
    let categories:         [RegisteredCategorySnapshot]
    let userProfile:        UserProfileSnapshot
    let currencyCode:       String
    let appLanguageCode:    String
    let localeIdentifier:   String
    let timeZoneIdentifier: String

    init(
        transactions: [TransactionSnapshot],
        goals: [GoalSnapshot],
        accounts: [AccountSnapshot],
        projects: [ProjectSnapshot],
        families: [FamilySnapshot],
        categories: [RegisteredCategorySnapshot],
        userProfile: UserProfileSnapshot,
        currencyCode: String,
        appLanguageCode: String,
        localeIdentifier: String,
        timeZoneIdentifier: String
    ) {
        self.transactions = transactions
        self.goals = goals
        self.accounts = accounts
        self.projects = projects
        self.families = families
        self.categories = categories
        self.userProfile = userProfile
        self.currencyCode = currencyCode
        self.appLanguageCode = appLanguageCode
        self.localeIdentifier = localeIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    static func registeredExpenseCategories(from categories: [Category]) -> [RegisteredCategorySnapshot] {
        categories
            .filter { $0.parent == nil && ($0.type == .expense || $0.type == .both) }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map {
                RegisteredCategorySnapshot(
                    systemKey: $0.systemKey,
                    displayName: $0.displayName
                )
            }
    }

    func formatCurrency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: localeIdentifier)
        return f.string(from: NSNumber(value: amount)) ?? "\(currencyCode) \(String(format: "%.2f", amount))"
    }
}

// MARK: - Availability

enum LocalAIAvailability {
    case available
    case needsAppleIntelligence
    case deviceNotEligible
    case requiresNewerOS
}

// MARK: - LocalAIService

enum LocalAIService {

    enum LocalAIError: LocalizedError {
        case notAvailable(String)
        case sessionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .notAvailable(let msg): return msg
            case .sessionFailed(let err): return err.localizedDescription
            }
        }
    }

    // MARK: - Availability check

    static func checkAvailability() -> LocalAIAvailability {
#if targetEnvironment(simulator)
        return .deviceNotEligible
#elseif canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return .needsAppleIntelligence
                default:
                    return .deviceNotEligible
                }
            @unknown default:
                return .deviceNotEligible
            }
        }
        return .requiresNewerOS
#else
        return .requiresNewerOS
#endif
    }

    // MARK: - System prompt

    static func buildSystemPrompt(context: FinanceContext, latestUserMessage: String = "") -> String {
        let tz  = TimeZone(identifier: context.timeZoneIdentifier) ?? .current
        let appLanguage = AppLanguage(rawValue: context.appLanguageCode) ?? LanguageManager.shared.effective
        let loc = appLanguage.locale
        let df  = DateFormatter()
        df.locale   = loc
        df.timeZone = tz
        df.dateStyle = .full
        df.timeStyle = .short
        let dateStr = df.string(from: Date())
        let tzName  = tz.localizedName(for: .standard, locale: loc) ?? context.timeZoneIdentifier

        let accountLines: String
        if context.accounts.isEmpty {
            accountLines = "  (no accounts registered)"
        } else {
            accountLines = context.accounts.map { acc in
                let tag = acc.isDefault ? " ★ default" : ""
                let aliases = acc.aliases.joined(separator: ", ")
                let forecast: String
                if acc.semanticType == "credit_card_account",
                   let estimatedBillAmount = acc.estimatedBillAmount,
                   let windowStart = acc.billingWindowStart,
                   let windowEnd = acc.billingWindowEnd {
                    let closing = acc.billingClosingDay.map(String.init) ?? "not defined"
                    let due = acc.paymentDueDay.map(String.init) ?? "not defined"
                    let days = acc.daysUntilClosing.map(String.init) ?? "0"
                    let availableCreditEstimate = acc.creditLimit.map {
                        context.formatCurrency($0 - estimatedBillAmount)
                    } ?? "User did not define a limit"
                    forecast = " | estimated_bill: \(context.formatCurrency(estimatedBillAmount)) | available_credit_estimate: \(availableCreditEstimate) | billing_window: \(windowStart.formatted(.dateTime.year().month().day())) to \(windowEnd.formatted(.dateTime.year().month().day())) | closing_day: \(closing) | due_day: \(due) | days_until_closing: \(days)"
                } else {
                    forecast = ""
                }
                let creditLimit = acc.creditLimit.map { " | credit_limit: \(context.formatCurrency($0))" } ?? " | credit_limit: User did not define a limit"
                return "  • \(acc.name) [\(acc.typeLabel)]\(tag) | semantic_type: \(acc.semanticType) | aliases: \(aliases)\(creditLimit)\(forecast)"
            }.joined(separator: "\n")
        }

        let categoryLines: String
        if context.categories.isEmpty {
            categoryLines = "  (no categories registered)"
        } else {
            categoryLines = context.categories.map { category in
                "  • \(category.displayName) [key: \(category.systemKey ?? "-")]"
            }.joined(separator: "\n")
        }

        let profileName = context.userProfile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileLines = [
            "  • name: \(profileName.isEmpty ? "not defined" : profileName)",
            "  • adults: \(context.userProfile.adultsCount)",
            "  • children: \(context.userProfile.childrenCount)"
        ].joined(separator: "\n")

        let familyLines: String
        if context.families.isEmpty {
            familyLines = "  (no families registered)"
        } else {
            familyLines = context.families.map { family in
                "  • \(family.name) | accounts: \(family.accountsCount) | goals: \(family.goalsCount)"
            }.joined(separator: "\n")
        }

        let projectLines: String
        if context.projects.isEmpty {
            projectLines = "  (no projects registered)"
        } else {
            projectLines = context.projects.map { project in
                let budget = project.budget.map { context.formatCurrency($0) } ?? "none"
                let description = project.description?.trimmingCharacters(in: .whitespacesAndNewlines)
                return "  • \(project.name) | status: \(project.isActive ? "active" : "inactive") | budget: \(budget) | spent: \(context.formatCurrency(project.spent)) | description: \(description?.isEmpty == false ? description! : "none")"
            }.joined(separator: "\n")
        }

        let relevantEntityLines = relevantEntitiesBlock(
            for: latestUserMessage,
            context: context
        )

        return """
        You are the personal finance assistant inside the finAInce app.
        Your only job is to help the user monitor expenses, understand spending patterns,
        and build healthier financial habits.

        ## App scope
        finAInce is strictly a personal expense tracking app.
        Do not discuss investments, market topics, loans, or banking products.

        ## Behavior rules
        - Reply in the user's preferred app language: \(responseLanguageInstruction(for: appLanguage)).
        - Be empathetic and never judge the user's spending habits.
        - Keep answers concise: at most 3 short paragraphs or one objective list.
        - Interpret the data instead of repeating raw numbers without context.
        - If the request is ambiguous or lacks key context such as period, category, or account,
          ask one direct clarification question before answering.
        - If the user asks whether they have a credit card, card bill, wallet, cash account, or checking account, inspect the registered accounts first.
        - If the user asks about their card, invoice, bill closing, current bill amount, closing forecast, card limit, or available card limit, inspect the credit card accounts and their estimated_bill, credit_limit, and available_credit_estimate fields first.
        - Treat these app concepts as distinct:
          • credit card account = account with semantic_type credit_card_account
          • cash / wallet = account with semantic_type cash_wallet_account
          • checking / bank account = account with semantic_type bank_checking_account
          • bill payment = a card bill payment transaction, not the same as a purchase on the card
          • cash withdrawal = moving money from checking to cash/wallet, not an expense by itself
          • card closing forecast = estimated sum of posted expense transactions inside the current billing window
        - If a credit card account shows credit_limit: User did not define a limit, suggest that the user add the card limit in the account settings, because that improves available-limit answers and card insights.

        ## Critical output rules
        - Never reveal chain-of-thought, internal reasoning, or intermediate steps.
        - Never mention tool names, function names, or that you are checking data.
        - Never start with phrases like "I'll check", "Let me verify", "Analyzing your data",
          or anything similar.
        - Present the answer directly, as if you naturally know the user's finances.
        - Tool outputs are internal context and must never be shown literally.
        - If the user explicitly asks to list transactions, list every transaction returned by buscar_transacoes up to the tool limit and attach direct details when helpful.
        - If the user did not explicitly ask for a full list, summarize only the most relevant 1 to 3 matches.
        - If the user asks for transactions but does not specify a period, assume the current month by default.

        ## Available tools (use silently)
        - buscar_transacoes   — filters expenses by period, category, or account
        - resumo_do_mes       — monthly totals and top categories
        - verificar_metas     — spending goal progress
        - consultar_contas    — account balances
        - consultar_entidades_financeiras — searches accounts, credit card forecast, goals, projects, and family context
        - criar_transacao     — creates a new expense and lets the app show a confirmation card

        ## When to call criar_transacao
        Call it immediately, without asking permission, when:
        1. The user explicitly says they spent money, for example: "I spent R$50 at the market"
        2. There is receipt or OCR data in the conversation. Extract amount, merchant, date,
           and category, then call the tool without describing the receipt in plain text.
           The app will display the confirmation card.

        ## Registered accounts (use in criar_transacao → accountName)
        \(accountLines)

        ## Registered expense categories (use in criar_transacao → categoryKey)
        \(categoryLines)

        ## User profile
        \(profileLines)

        ## Registered families
        \(familyLines)

        ## Registered projects
        \(projectLines)

        ## Entities most relevant to the latest user request
        \(relevantEntityLines)

        ## User context
        Current date/time : \(dateStr)
        Time zone         : \(tzName)
        Currency          : \(context.currencyCode)
        App language      : \(appLanguage.displayName)
        Locale            : \(context.localeIdentifier)
        """
    }

    // MARK: - Send

    static func send(
        userMessage: String,
        conversationHistory: String = "",
        context: FinanceContext
    ) async throws -> (content: String, draft: TransactionDraft?) {
#if targetEnvironment(simulator)
        throw LocalAIError.notAvailable(
            "A IA no dispositivo não funciona no Simulador. " +
            "Teste em um iPhone real com Apple Intelligence ativado."
        )
#elseif canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: break
            case .unavailable(let reason):
                let msg: String
                switch reason {
                case .appleIntelligenceNotEnabled:
                    msg = "Para usar a IA no dispositivo, ative o Apple Intelligence " +
                          "em Ajustes > Apple Intelligence e Siri."
                case .deviceNotEligible:
                    msg = "Seu dispositivo não é compatível com Apple Intelligence. " +
                          "É necessário iPhone 15 Pro ou superior com iOS 26."
                @unknown default:
                    msg = "IA local indisponível. Verifique se o Apple Intelligence está ativado."
                }
                throw LocalAIError.notAvailable(msg)
            @unknown default:
                throw LocalAIError.notAvailable("IA local indisponível no momento.")
            }

            let fullPrompt = conversationHistory.isEmpty
                ? userMessage
                : "\(conversationHistory)\n\nUsuário: \(userMessage)"

            let systemPrompt = buildSystemPrompt(context: context, latestUserMessage: userMessage)
            let relevantEntityLines = relevantEntitiesBlock(for: userMessage, context: context)
            debugPrintPrompt(label: "AI Local Prompt", prompt: systemPrompt)
            debugPrintRAG(label: "AI Local Retrieval", query: userMessage, entityBlock: relevantEntityLines)
            let draftBox     = DraftBox()

            do {
                let session = LanguageModelSession(
                    tools: [
                        BuscarTransacoesTool(ctx: context),
                        ResumoDoMesTool(ctx: context),
                        VerificarMetasTool(ctx: context),
                        ConsultarContasTool(ctx: context),
                        ConsultarEntidadesFinanceirasTool(ctx: context),
                        CriarTransacaoTool(ctx: context, box: draftBox),
                    ],
                    instructions: systemPrompt
                )
                let response = try await session.respond(to: fullPrompt)
                let draft    = await draftBox.draft
                return (response.content, draft)
            } catch let error as LocalAIError {
                throw error
            } catch {
                throw LocalAIError.sessionFailed(error)
            }
        }
        throw LocalAIError.notAvailable("A IA no dispositivo requer iOS 26 ou superior.")
#else
        throw LocalAIError.notAvailable("A IA no dispositivo requer iOS 26 ou superior.")
#endif
    }

    // MARK: - Classify (no tools, no finance persona — pure text classification)

    /// Sends a plain classification question to Apple Intelligence using a minimal session
    /// with no tools and no finance persona, so the model cannot accidentally call tools.
    /// Returns the trimmed response string, or nil if unavailable / failed.
    /// Isolated session for short free-text generation (insights, summaries).
    /// No tools, no finance persona — just a brief advisor persona.
    static func generate(prompt: String) async -> String? {
#if targetEnvironment(simulator)
        return nil
#elseif canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            do {
                let session = LanguageModelSession(
                    instructions: """
                    You are a personal finance advisor. Reply in the user's preferred app language: \(responseLanguageInstruction(for: LanguageManager.shared.effective)). \
                    Be direct and practical — 1 or 2 sentences maximum. No greetings, no markdown, \
                    no lists. Do not use any tools or create transactions.
                    """
                )
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        return nil
#else
        return nil
#endif
    }

    static func classify(prompt: String) async -> String? {
#if targetEnvironment(simulator)
        return nil
#elseif canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            do {
                let session = LanguageModelSession(
                    instructions: "You are a concise classifier. Reply with only what is asked — a single word or short phrase from the provided list. Do not explain, do not create transactions, do not use any tools."
                )
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        return nil
#else
        return nil
#endif
    }

    private static func responseLanguageInstruction(for language: AppLanguage) -> String {
        switch language {
        case .ptBR:
            return "Brazilian Portuguese (pt-BR)"
        case .en:
            return "English (en)"
        case .es:
            return "Spanish (es)"
        case .system:
            return responseLanguageInstruction(for: LanguageManager.shared.effective)
        }
    }

    private static func searchTokens(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
            .map(financeNormalizeForMatching)
            .filter { !$0.isEmpty }
    }

    private static func entityScore(tokens: [String], haystack: String) -> Int {
        var score = 0
        for token in tokens {
            if token.count >= 4 && haystack.contains(token) {
                score += 3
            } else if token.count >= 3 && haystack.contains(token) {
                score += 2
            }
        }
        return score
    }

    static func relevantEntitiesBlock(for query: String, context: FinanceContext) -> String {
        let tokens = searchTokens(from: query)
        guard !tokens.isEmpty else {
            return "  (no explicit entity search terms detected)"
        }

        struct Match {
            let score: Int
            let line: String
        }

        var matches: [Match] = []

        for account in context.accounts {
            let haystack = ([account.name, account.typeLabel, account.semanticType] + account.aliases)
                .map(financeNormalizeForMatching)
                .joined(separator: " ")
            let score = entityScore(tokens: tokens, haystack: haystack)
            if score > 0 {
                matches.append(.init(
                    score: score,
                    line: "  • account: \(account.name) [\(account.typeLabel)] | semantic_type: \(account.semanticType) | balance: \(context.formatCurrency(account.balance))"
                ))
            }
        }

        for goal in context.goals {
            let haystack = [goal.title, goal.categoryName ?? ""]
                .map(financeNormalizeForMatching)
                .joined(separator: " ")
            let score = entityScore(tokens: tokens, haystack: haystack)
            if score > 0 {
                matches.append(.init(
                    score: score,
                    line: "  • goal: \(goal.title) | category: \(goal.categoryName ?? "all spending") | target: \(context.formatCurrency(goal.targetAmount))"
                ))
            }
        }

        for project in context.projects {
            let haystack = [project.name, project.description ?? ""]
                .map(financeNormalizeForMatching)
                .joined(separator: " ")
            let score = entityScore(tokens: tokens, haystack: haystack)
            if score > 0 {
                matches.append(.init(
                    score: score,
                    line: "  • project: \(project.name) | status: \(project.isActive ? "active" : "inactive") | spent: \(context.formatCurrency(project.spent))"
                ))
            }
        }

        for family in context.families {
            let haystack = financeNormalizeForMatching(family.name)
            let score = entityScore(tokens: tokens, haystack: haystack)
            if score > 0 {
                matches.append(.init(
                    score: score,
                    line: "  • family: \(family.name) | accounts: \(family.accountsCount) | goals: \(family.goalsCount)"
                ))
            }
        }

        guard !matches.isEmpty else {
            return "  (no direct account, family, goal, or project matches found)"
        }

        return matches
            .sorted { $0.score > $1.score }
            .prefix(8)
            .map(\.line)
            .joined(separator: "\n")
    }

    private static func debugPrintPrompt(label: String, prompt: String) {
#if DEBUG
        print("\n========== \(label) ==========\n\(prompt)\n========== END \(label) ==========\n")
#endif
    }

    private static func debugPrintRAG(label: String, query: String, entityBlock: String) {
#if DEBUG
        print(
            """

            ========== \(label) ==========
            Query:
            \(query.isEmpty ? "None." : query)

            Entities RAG:
            \(entityBlock)
            ========== END \(label) ==========

            """
        )
#endif
    }
}

// MARK: - Tools (device-only: FoundationModelsMacros plugin is not in the Simulator SDK)

#if canImport(FoundationModels) && !targetEnvironment(simulator)

private enum AIToolLogger {
    nonisolated static func log(_ label: String, payload: String) {
#if DEBUG
        print("\n[AI Tool] \(label)\n\(payload)\n")
#endif
    }
}

// ── Buscar Transações ──────────────────────────────────────────────────────

@available(iOS 26.0, *)
struct BuscarTransacoesTool: Tool {
    let name        = "buscar_transacoes"
    let description = """
    Busca despesas do usuário com filtros opcionais de período, categoria e conta.
    Use para responder perguntas sobre gastos específicos.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Mês de 1 a 12. Omitir para todos os meses.")
        var mes: Int?
        @Guide(description: "Ano com 4 dígitos. Omitir para o ano atual.")
        var ano: Int?
        @Guide(description: "Nome parcial da categoria. Omitir para todas.")
        var categoria: String?
        @Guide(description: "Nome parcial da conta. Omitir para todas.")
        var conta: String?
        @Guide(description: "Máximo de itens a retornar. Padrão 50.")
        var limite: Int?
    }

    let ctx: FinanceContext

    func call(arguments: Arguments) async throws -> String {
        AIToolLogger.log(
            "buscar_transacoes",
            payload: "mes=\(arguments.mes.map(String.init) ?? "nil") | ano=\(arguments.ano.map(String.init) ?? "nil") | categoria=\(arguments.categoria ?? "nil") | conta=\(arguments.conta ?? "nil") | limite=\(arguments.limite.map(String.init) ?? "nil")"
        )
        let cal         = Calendar.current
        let now         = Date()
        let targetYear  = arguments.ano ?? cal.component(.year, from: now)

        var results = ctx.transactions.filter(\.isExpense)

        let targetMonth = arguments.mes ?? cal.component(.month, from: now)
        results = results.filter {
            cal.component(.year,  from: $0.date) == targetYear &&
            cal.component(.month, from: $0.date) == targetMonth
        }
        if let cat = arguments.categoria {
            results = results.filter {
                $0.categoryName.localizedCaseInsensitiveContains(cat) ||
                ($0.subcategoryName?.localizedCaseInsensitiveContains(cat) ?? false)
            }
        }
        if let conta = arguments.conta {
            results = results.filter {
                $0.accountName.localizedCaseInsensitiveContains(conta)
            }
        }

        results = Array(results.sorted { $0.date > $1.date }.prefix(arguments.limite ?? 50))

        guard !results.isEmpty else {
            let result = "Nenhuma despesa encontrada com esses filtros."
            AIToolLogger.log("buscar_transacoes.result", payload: result)
            return result
        }

        let total = results.reduce(0.0) { $0 + $1.amount }
        let lines = results.map { tx -> String in
            let d     = tx.date.formatted(.dateTime.day().month(.abbreviated))
            let place = tx.placeName ?? tx.categoryName
            let sub   = tx.subcategoryName.map { " / \($0)" } ?? ""
            return "• \(d) | \(ctx.formatCurrency(tx.amount)) | \(place) [\(tx.categoryName)\(sub)]"
        }.joined(separator: "\n")

        let result = "\(results.count) despesa(s) — Total: \(ctx.formatCurrency(total))\n\(lines)"
        AIToolLogger.log("buscar_transacoes.result", payload: result)
        return result
    }
}

// ── Resumo do Mês ──────────────────────────────────────────────────────────

@available(iOS 26.0, *)
struct ResumoDoMesTool: Tool {
    let name        = "resumo_do_mes"
    let description = """
    Resumo financeiro de um mês: total gasto, top categorias de gasto
    e variação em relação ao mês anterior.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Mês de 1 a 12. Omitir para o mês atual.")
        var mes: Int?
        @Guide(description: "Ano com 4 dígitos. Omitir para o ano atual.")
        var ano: Int?
    }

    let ctx: FinanceContext

    func call(arguments: Arguments) async throws -> String {
        AIToolLogger.log(
            "resumo_do_mes",
            payload: "mes=\(arguments.mes.map(String.init) ?? "nil") | ano=\(arguments.ano.map(String.init) ?? "nil")"
        )
        let cal          = Calendar.current
        let now          = Date()
        let targetMonth  = arguments.mes ?? cal.component(.month, from: now)
        let targetYear   = arguments.ano ?? cal.component(.year,  from: now)

        guard (1...12).contains(targetMonth) else {
            let result = "Não consegui gerar o resumo: o mês informado precisa estar entre 1 e 12."
            AIToolLogger.log("resumo_do_mes.result", payload: result)
            return result
        }

        let monthTx = ctx.transactions.filter {
            $0.isExpense &&
            cal.component(.year,  from: $0.date) == targetYear &&
            cal.component(.month, from: $0.date) == targetMonth
        }
        let prevMonth = targetMonth == 1 ? 12 : targetMonth - 1
        let prevYear  = targetMonth == 1 ? targetYear - 1 : targetYear
        let prevTotal = ctx.transactions.filter {
            $0.isExpense &&
            cal.component(.year,  from: $0.date) == prevYear &&
            cal.component(.month, from: $0.date) == prevMonth
        }.reduce(0.0) { $0 + $1.amount }

        let total = monthTx.reduce(0.0) { $0 + $1.amount }

        var byCat: [String: Double] = [:]
        for tx in monthTx { byCat[tx.categoryName, default: 0] += tx.amount }
        let topCats = byCat.sorted { $0.value > $1.value }.prefix(5)
            .map { "  • \($0.key): \(ctx.formatCurrency($0.value))" }
            .joined(separator: "\n")

        let varStr: String
        if prevTotal > 0 {
            let pct  = ((total - prevTotal) / prevTotal) * 100
            let sign = pct >= 0 ? "+" : ""
            varStr   = "\(sign)\(String(format: "%.1f", pct))% vs mês anterior"
        } else {
            varStr = "sem dados do mês anterior"
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: ctx.localeIdentifier)
        let monthName = df.monthSymbols.indices.contains(targetMonth - 1)
            ? df.monthSymbols[targetMonth - 1].capitalized
            : "Mês \(targetMonth)"

        let result = """
        Resumo de \(monthName)/\(targetYear):
        Total gasto : \(ctx.formatCurrency(total)) (\(varStr))
        Transações  : \(monthTx.count)

        Top categorias:
        \(topCats.isEmpty ? "  Nenhuma despesa registrada." : topCats)
        """
        AIToolLogger.log("resumo_do_mes.result", payload: result)
        return result
    }
}

// ── Verificar Metas ────────────────────────────────────────────────────────

@available(iOS 26.0, *)
struct VerificarMetasTool: Tool {
    let name        = "verificar_metas"
    let description = """
    Retorna o progresso das metas de gasto do usuário para o mês atual.
    Mostra quanto foi gasto versus o limite de cada meta.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Nome parcial da meta para filtrar. Omitir para todas.")
        var nomeMeta: String?
    }

    let ctx: FinanceContext

    func call(arguments: Arguments) async throws -> String {
        AIToolLogger.log(
            "verificar_metas",
            payload: "nomeMeta=\(arguments.nomeMeta ?? "nil")"
        )
        var goals = ctx.goals
        if let nome = arguments.nomeMeta {
            goals = goals.filter { $0.title.localizedCaseInsensitiveContains(nome) }
        }
        guard !goals.isEmpty else {
            let result = "Nenhuma meta cadastrada. Crie metas em Perfil > Metas de Gastos."
            AIToolLogger.log("verificar_metas.result", payload: result)
            return result
        }

        let lines = goals.map { g -> String in
            let pct    = g.percentUsed
            let filled = min(Int(pct / 10), 10)
            let bar    = String(repeating: "█", count: filled) +
                         String(repeating: "░", count: 10 - filled)
            let status = g.isOverLimit  ? "⚠️ Acima do limite"  :
                         g.isNearLimit  ? "🟡 Próximo do limite" :
                                          "✅ Dentro do limite"
            let cat = g.categoryName ?? "Todos os gastos"
            return """
            \(g.emoji) \(g.title) [\(cat)]
            \(bar) \(String(format: "%.0f", pct))%
            \(ctx.formatCurrency(g.monthlySpend)) / \(ctx.formatCurrency(g.targetAmount)) — \(status)
            """
        }.joined(separator: "\n\n")

        AIToolLogger.log("verificar_metas.result", payload: lines)
        return lines
    }
}

// ── Consultar Contas ───────────────────────────────────────────────────────

@available(iOS 26.0, *)
struct ConsultarContasTool: Tool {
    let name        = "consultar_contas"
    let description = "Retorna os detalhes principais de cada conta cadastrada no app, com foco em tipo e contexto de cartão."

    @Generable
    struct Arguments {
        @Guide(description: "Nome parcial da conta para filtrar. Omitir para todas.")
        var nomeConta: String?
    }

    let ctx: FinanceContext

    func call(arguments: Arguments) async throws -> String {
        AIToolLogger.log("consultar_contas", payload: "nomeConta=\(arguments.nomeConta ?? "nil")")
        func normalize(_ text: String) -> String {
            text
                .lowercased()
                .replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
                .folding(options: [.diacriticInsensitive], locale: .current)
        }

        var accounts = ctx.accounts
        if let nome = arguments.nomeConta {
            let query = normalize(nome)
            accounts = accounts.filter { account in
                let haystack = ([account.name, account.typeLabel, account.semanticType] + account.aliases)
                    .map(normalize)
                    .joined(separator: " ")
                return haystack.contains(query)
            }
        }
        guard !accounts.isEmpty else {
            return ("Nenhuma conta encontrada.")
        }

        let lines = accounts.map { acc -> String in
            let def = acc.isDefault ? " (padrão)" : ""
            let creditLimit = acc.creditLimit.map { " | limite: \(ctx.formatCurrency($0))" } ?? " | limite: Usuário não definiu um limite"
            let availableCredit = if let creditLimitValue = acc.creditLimit, let estimatedBill = acc.estimatedBillAmount {
                " | limite disponível estimado: \(ctx.formatCurrency(creditLimitValue - estimatedBill))"
            } else {
                ""
            }
            return "• \(acc.name) [\(acc.typeLabel)]\(def)\(creditLimit)\(availableCredit)"
        }.joined(separator: "\n")
        AIToolLogger.log("consultar_contas.result", payload: lines)
        return (lines)
    }
}

@available(iOS 26.0, *)
struct ConsultarEntidadesFinanceirasTool: Tool {
    let name = "consultar_entidades_financeiras"
    let description = """
    Busca contexto financeiro fora das transações: contas, cartões com previsão de fechamento,
    metas, projetos e família. Use para perguntas sobre cartão, fatura, conta corrente,
    carteira, metas, projetos ou perfil familiar.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Texto curto com o assunto buscado, como 'cartao', 'fatura', 'carteira', 'meta viagem', 'projeto casa'.")
        var termo: String
    }

    let ctx: FinanceContext

    func call(arguments: Arguments) async throws -> String {
        AIToolLogger.log("consultar_entidades_financeiras", payload: "termo=\(arguments.termo)")
        let block = LocalAIService.relevantEntitiesBlock(for: arguments.termo, context: ctx)
        let accountDetails = ctx.accounts
            .filter { account in
                let haystack = ([account.name, account.typeLabel, account.semanticType] + account.aliases)
                    .joined(separator: " ")
                    .lowercased()
                return haystack.contains(arguments.termo.lowercased())
            }
            .map { account in
                var line = "• \(account.name) [\(account.typeLabel)]"
                if let creditLimit = account.creditLimit {
                    line += " | limite: \(ctx.formatCurrency(creditLimit))"
                } else {
                    line += " | limite: Usuário não definiu um limite"
                }
                if let estimatedBillAmount = account.estimatedBillAmount {
                    line += " | fatura estimada: \(ctx.formatCurrency(estimatedBillAmount))"
                    if let creditLimit = account.creditLimit {
                        line += " | limite disponível estimado: \(ctx.formatCurrency(creditLimit - estimatedBillAmount))"
                    }
                }
                if let daysUntilClosing = account.daysUntilClosing {
                    line += " | dias para fechar: \(daysUntilClosing)"
                }
                return line
            }
            .joined(separator: "\n")

        if accountDetails.isEmpty {
            AIToolLogger.log("consultar_entidades_financeiras.result", payload: block)
            return block
        }

        let result = "\(block)\n\n\(accountDetails)"
        AIToolLogger.log("consultar_entidades_financeiras.result", payload: result)
        return result
    }
}

// ── DraftBox (passa rascunho da tool para fora da sessão) ──────────────────

@available(iOS 26.0, *)
actor DraftBox {
    private(set) var draft: TransactionDraft?
    func set(_ d: TransactionDraft) { draft = d }
}

// ── Criar Transação ────────────────────────────────────────────────────────

@available(iOS 26.0, *)
struct CriarTransacaoTool: Tool {
    let name        = "criar_transacao"
    let description = """
    Registers a new expense. Call this tool in TWO scenarios:
    1. The user explicitly says they want to log an expense
       (e.g. "gastei R$50 no mercado", "anota uma despesa de gasolina de R$120").
    2. Receipt / OCR data is present in the conversation — extract amount, place,
       date and category and call this tool IMMEDIATELY without asking the user first.
    A confirmation card appears for the user to approve before anything is saved.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Amount as a positive decimal in the user's currency.")
        var amount: Double

        @Guide(description: """
        Best-matching registered expense category key from the system prompt list.
        Prefer the exact key value when available. Leave empty only if no category fits.
        """)
        var categoryKey: String?

        @Guide(description: "Best-matching expense category label for display if needed.")
        var category: String

        @Guide(description: "Establishment name or brief description of the purchase.")
        var placeName: String

        @Guide(description: "Optional short note about this expense.")
        var notes: String?

        @Guide(description: """
        Transaction date in ISO 8601 format YYYY-MM-DD. \
        Extract from the receipt when available; otherwise use today's date.
        """)
        var date: String?

        @Guide(description: """
        Name of one of the user's registered accounts to debit. \
        Pick the best match from the registered accounts list in the system prompt. \
        Leave empty to use the default account.
        """)
        var accountName: String?
    }

    let ctx: FinanceContext
    let box: DraftBox

    func call(arguments: Arguments) async throws -> String {
        AIToolLogger.log(
            "criar_transacao",
            payload: "amount=\(arguments.amount) | categoryKey=\(arguments.categoryKey ?? "nil") | category=\(arguments.category) | placeName=\(arguments.placeName) | date=\(arguments.date ?? "nil") | accountName=\(arguments.accountName ?? "nil")"
        )
        // Parse ISO date string → Date (nil = today)
        let txDate: Date?
        if let dateStr = arguments.date, !dateStr.isEmpty {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withFullDate]
            txDate = fmt.date(from: dateStr)
        } else {
            txDate = nil
        }

        let draft = TransactionDraft(
            amount:       max(0.01, arguments.amount),
            typeRaw:      "expense",
            categorySystemKey: arguments.categoryKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryName: arguments.category,
            placeName:    arguments.placeName,
            notes:        arguments.notes ?? "",
            date:         txDate,
            accountName:  arguments.accountName ?? "",
            receiptImageData: nil
        )
        await box.set(draft)
        let result = """
        Draft created: \(ctx.formatCurrency(draft.amount)) — \
        \(draft.placeName) [\(draft.categoryName)].
        A confirmation card is now shown to the user. \
        Tell the user a confirmation card appeared and they can approve or cancel.
        """
        AIToolLogger.log("criar_transacao.result", payload: result)
        return result
    }
}

#endif // canImport(FoundationModels) && !targetEnvironment(simulator)
