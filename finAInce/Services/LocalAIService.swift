// LocalAIService.swift
// IA on-device via Apple Intelligence (FoundationModels · iOS 26+)
// Compila em qualquer target — todo o código runtime está protegido por
// #if canImport(FoundationModels) + #available(iOS 26, *)

import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Thread-safe snapshots (plain Sendable structs, sem SwiftData)

struct TransactionSnapshot: Sendable {
    let id: UUID
    let amount: Double
    let typeRaw: String          // "expense" | "transfer"
    let categoryName: String
    let subcategoryName: String?
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
    let balance: Double
    let isDefault: Bool
}

// MARK: - SwiftData → Snapshot helpers

extension Transaction {
    func asSnapshot() -> TransactionSnapshot {
        TransactionSnapshot(
            id:              id,
            amount:          amount,
            typeRaw:         type.rawValue,
            categoryName:    category?.name    ?? "Sem categoria",
            subcategoryName: subcategory?.name,
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
            categoryName: category?.name,
            monthlySpend: spend
        )
    }
}

extension Account {
    func asSnapshot() -> AccountSnapshot {
        AccountSnapshot(
            name:      name,
            typeLabel: type.label,
            balance:   balance,
            isDefault: isDefault
        )
    }
}

// MARK: - FinanceContext (pacote completo enviado ao modelo)

struct FinanceContext: Sendable {
    let transactions:       [TransactionSnapshot]
    let goals:              [GoalSnapshot]
    let accounts:           [AccountSnapshot]
    let currencyCode:       String
    let appLanguageCode:    String
    let localeIdentifier:   String
    let timeZoneIdentifier: String

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

    static func buildSystemPrompt(context: FinanceContext) -> String {
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
                return "  • \(acc.name) [\(acc.typeLabel)]\(tag)"
            }.joined(separator: "\n")
        }

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

        ## Critical output rules
        - Never reveal chain-of-thought, internal reasoning, or intermediate steps.
        - Never mention tool names, function names, or that you are checking data.
        - Never start with phrases like "I'll check", "Let me verify", "Analyzing your data",
          or anything similar.
        - Present the answer directly, as if you naturally know the user's finances.
        - Tool outputs are internal context and must never be shown literally.

        ## Available tools (use silently)
        - buscar_transacoes   — filters expenses by period, category, or account
        - resumo_do_mes       — monthly totals and top categories
        - verificar_metas     — spending goal progress
        - consultar_contas    — account balances
        - criar_transacao     — creates a new expense and lets the app show a confirmation card

        ## When to call criar_transacao
        Call it immediately, without asking permission, when:
        1. The user explicitly says they spent money, for example: "I spent R$50 at the market"
        2. There is receipt or OCR data in the conversation. Extract amount, merchant, date,
           and category, then call the tool without describing the receipt in plain text.
           The app will display the confirmation card.

        ## Registered accounts (use in criar_transacao → accountName)
        \(accountLines)

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

            let systemPrompt = buildSystemPrompt(context: context)
            let draftBox     = DraftBox()

            do {
                let session = LanguageModelSession(
                    tools: [
                        BuscarTransacoesTool(ctx: context),
                        ResumoDoMesTool(ctx: context),
                        VerificarMetasTool(ctx: context),
                        ConsultarContasTool(ctx: context),
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
}

// MARK: - Tools (device-only: FoundationModelsMacros plugin is not in the Simulator SDK)

#if canImport(FoundationModels) && !targetEnvironment(simulator)

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
        @Guide(description: "Máximo de itens a retornar. Padrão 20.")
        var limite: Int?
    }

    let ctx: FinanceContext

    func call(arguments: Arguments) async throws -> String {
        let cal         = Calendar.current
        let now         = Date()
        let targetYear  = arguments.ano ?? cal.component(.year, from: now)

        var results = ctx.transactions.filter(\.isExpense)

        if let month = arguments.mes {
            results = results.filter {
                cal.component(.year,  from: $0.date) == targetYear &&
                cal.component(.month, from: $0.date) == month
            }
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

        results = Array(results.sorted { $0.date > $1.date }.prefix(arguments.limite ?? 20))

        guard !results.isEmpty else {
            return ("Nenhuma despesa encontrada com esses filtros.")
        }

        let total = results.reduce(0.0) { $0 + $1.amount }
        let lines = results.map { tx -> String in
            let d     = tx.date.formatted(.dateTime.day().month(.abbreviated))
            let place = tx.placeName ?? tx.categoryName
            let sub   = tx.subcategoryName.map { " / \($0)" } ?? ""
            return "• \(d) | \(ctx.formatCurrency(tx.amount)) | \(place) [\(tx.categoryName)\(sub)]"
        }.joined(separator: "\n")

        return (
            "\(results.count) despesa(s) — Total: \(ctx.formatCurrency(total))\n\(lines)"
        )
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
        let cal          = Calendar.current
        let now          = Date()
        let targetMonth  = arguments.mes ?? cal.component(.month, from: now)
        let targetYear   = arguments.ano ?? cal.component(.year,  from: now)

        guard (1...12).contains(targetMonth) else {
            return "Não consegui gerar o resumo: o mês informado precisa estar entre 1 e 12."
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

        return ("""
        Resumo de \(monthName)/\(targetYear):
        Total gasto : \(ctx.formatCurrency(total)) (\(varStr))
        Transações  : \(monthTx.count)

        Top categorias:
        \(topCats.isEmpty ? "  Nenhuma despesa registrada." : topCats)
        """)
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
        var goals = ctx.goals
        if let nome = arguments.nomeMeta {
            goals = goals.filter { $0.title.localizedCaseInsensitiveContains(nome) }
        }
        guard !goals.isEmpty else {
            return (
                "Nenhuma meta cadastrada. Crie metas em Perfil > Metas de Gastos."
            )
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

        return (lines)
    }
}

// ── Consultar Contas ───────────────────────────────────────────────────────

@available(iOS 26.0, *)
struct ConsultarContasTool: Tool {
    let name        = "consultar_contas"
    let description = "Retorna os saldos e tipo de cada conta cadastrada no app."

    @Generable
    struct Arguments {
        @Guide(description: "Nome parcial da conta para filtrar. Omitir para todas.")
        var nomeConta: String?
    }

    let ctx: FinanceContext

    func call(arguments: Arguments) async throws -> String {
        var accounts = ctx.accounts
        if let nome = arguments.nomeConta {
            accounts = accounts.filter { $0.name.localizedCaseInsensitiveContains(nome) }
        }
        guard !accounts.isEmpty else {
            return ("Nenhuma conta encontrada.")
        }

        let lines = accounts.map { acc -> String in
            let def = acc.isDefault ? " (padrão)" : ""
            return "• \(acc.name) [\(acc.typeLabel)]\(def): \(ctx.formatCurrency(acc.balance))"
        }.joined(separator: "\n")

        let total = accounts.reduce(0.0) { $0 + $1.balance }
        return ("\(lines)\n\nSaldo total: \(ctx.formatCurrency(total))")
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

        @Guide(description: "Best-matching expense category name (e.g. Supermercado, Restaurantes, Transporte, Saúde).")
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
            categoryName: arguments.category,
            placeName:    arguments.placeName,
            notes:        arguments.notes ?? "",
            date:         txDate,
            accountName:  arguments.accountName ?? "",
            receiptImageData: nil
        )
        await box.set(draft)
        return """
        Draft created: \(ctx.formatCurrency(draft.amount)) — \
        \(draft.placeName) [\(draft.categoryName)].
        A confirmation card is now shown to the user. \
        Tell the user a confirmation card appeared and they can approve or cancel.
        """
    }
}

#endif // canImport(FoundationModels) && !targetEnvironment(simulator)
