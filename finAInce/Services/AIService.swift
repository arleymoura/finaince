import Foundation

// MARK: - Transaction draft (rascunho criado pela tool CriarTransacao)

struct TransactionDraft: Sendable {
    let amount:       Double
    let typeRaw:      String   // "expense"
    let categorySystemKey: String?
    let categoryName: String
    let placeName:    String
    let notes:        String
    /// Data da transação extraída do recibo/contexto. nil = hoje.
    let date:         Date?
    /// Nome da conta de destino sugerida. "" = conta padrão.
    let accountName:  String
    let receiptImageData: Data?
}

// MARK: - AIService result (content + optional transaction draft from on-device AI)

struct AIServiceResult {
    let content: String
    let transactionDraft: TransactionDraft?
    init(_ content: String, draft: TransactionDraft? = nil) {
        self.content = content
        self.transactionDraft = draft
    }
}

struct AIService {

    // MARK: - Error

    enum AIError: LocalizedError {
        case noAPIKey
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "Chave de API não encontrada. Configure novamente em Configurações."
            case .invalidResponse:
                return "Resposta inesperada do servidor. Tente novamente."
            case .apiError(let msg):
                return msg
            }
        }
    }

    // MARK: - Entry point

    static func send(
        messages: [ChatMessage],
        settings: AISettings,
        transactions: [Transaction],
        goals: [Goal] = [],
        accounts: [Account] = [],
        categories: [Category] = [],
        currencyCode: String = CurrencyOption.defaultCode,
        imageData: Data? = nil
    ) async throws -> AIServiceResult {

        // ── On-device Apple Intelligence (sem chave de API) ────────────────
        if settings.provider == .local {
            let cal = Calendar.current
            let now = Date()
            let thisMonthExpenses = transactions.filter {
                $0.type == .expense &&
                cal.component(.year,  from: $0.date) == cal.component(.year,  from: now) &&
                cal.component(.month, from: $0.date) == cal.component(.month, from: now)
            }
            let context = FinanceContext(
                transactions:       transactions.map { $0.asSnapshot() },
                goals:              goals.map { $0.asSnapshot(monthExpenses: thisMonthExpenses) },
                accounts:           accounts.map { $0.asSnapshot() },
                categories:         FinanceContext.registeredExpenseCategories(from: categories),
                currencyCode:       currencyCode,
                appLanguageCode:    LanguageManager.shared.effective.rawValue,
                localeIdentifier:   Locale.current.identifier,
                timeZoneIdentifier: TimeZone.current.identifier
            )
            let history = messages.dropLast().suffix(8).map { msg in
                "\(msg.role == .user ? "Usuário" : "Assistente"): \(msg.content)"
            }.joined(separator: "\n")

            let (content, draft) = try await LocalAIService.send(
                userMessage:         messages.last?.content ?? "",
                conversationHistory: history,
                context:             context
            )
            return AIServiceResult(content, draft: draft)
        }

        let system = buildSystemPrompt(transactions: transactions)

        // ── Provedores cloud ───────────────────────────────────────────────
        guard let apiKey = KeychainHelper.load(forKey: settings.provider.keychainKey),
              !apiKey.isEmpty else {
            throw AIError.noAPIKey
        }

        switch settings.provider {
        case .local:
            fatalError("handled above")   // unreachable
        case .groq:
            let t = try await sendOpenAICompatible(
                messages: messages, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.groq.com/openai/v1/chat/completions",
                providerName: "Groq", imageData: nil   // Groq default models sem visão
            )
            return AIServiceResult(t)
        case .deepseek:
            let t = try await sendOpenAICompatible(
                messages: messages, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.deepseek.com/v1/chat/completions",
                providerName: "DeepSeek", imageData: nil   // DeepSeek sem visão
            )
            return AIServiceResult(t)
        case .gemini:
            let t = try await sendGemini(
                messages: messages, model: settings.model, apiKey: apiKey, system: system,
                imageData: imageData
            )
            return AIServiceResult(t)
        case .openai:
            let t = try await sendOpenAICompatible(
                messages: messages, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.openai.com/v1/chat/completions",
                providerName: "OpenAI", imageData: imageData
            )
            return AIServiceResult(t)
        case .anthropic:
            let t = try await sendAnthropic(
                messages: messages, model: settings.model, apiKey: apiKey, system: system,
                imageData: imageData
            )
            return AIServiceResult(t)
        case .openrouter:
            let t = try await sendOpenAICompatible(
                messages: messages, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://openrouter.ai/api/v1/chat/completions",
                providerName: "OpenRouter", imageData: nil
            )
            return AIServiceResult(t)
        case .cerebras:
            let t = try await sendOpenAICompatible(
                messages: messages, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.cerebras.ai/v1/chat/completions",
                providerName: "Cerebras", imageData: nil
            )
            return AIServiceResult(t)
        case .huggingface:
            let t = try await sendOpenAICompatible(
                messages: messages, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://router.huggingface.co/v1/chat/completions",
                providerName: "Hugging Face", imageData: nil
            )
            return AIServiceResult(t)
        case .mistral:
            let t = try await sendOpenAICompatible(
                messages: messages, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.mistral.ai/v1/chat/completions",
                providerName: "Mistral", imageData: nil
            )
            return AIServiceResult(t)
        case .cohere:
            let t = try await sendCohere(
                messages: messages, model: settings.model, apiKey: apiKey, system: system
            )
            return AIServiceResult(t)
        }
    }

    // MARK: - System prompt

    private static func buildSystemPrompt(transactions: [Transaction]) -> String {
        let cal = Calendar.current
        let now = Date()
        let year  = cal.component(.year,  from: now)
        let month = cal.component(.month, from: now)
        let appLanguage = LanguageManager.shared.effective
        let currentMonthName = now.formatted(.dateTime.month(.wide))
        let currentYear = cal.component(.year, from: now)
        let currentMonthNumber = cal.component(.month, from: now)

        let thisMonth = transactions.filter {
            cal.component(.year,  from: $0.date) == year &&
            cal.component(.month, from: $0.date) == month &&
            $0.type == .expense
        }

        let total = thisMonth.reduce(0) { $0 + $1.amount }

        // Agrupa por categoria
        var byCategory: [String: Double] = [:]
        for tx in thisMonth {
            let cat = tx.category?.displayName ?? "Uncategorized"
            byCategory[cat, default: 0] += tx.amount
        }
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = appLanguage.locale
        func brl(_ v: Double) -> String { fmt.string(from: NSNumber(value: v)) ?? "\(v)" }

        let catLines = byCategory
            .sorted { $0.value > $1.value }
            .map { "• \($0.key): \(brl($0.value))" }
            .joined(separator: "\n")

        let txLines = thisMonth.prefix(30).map { tx in
            let place = tx.placeName ?? "unknown merchant"
            let cat   = tx.category?.displayName ?? "uncategorized"
            return "• \(brl(tx.amount)) — \(place) (\(cat))"
        }.joined(separator: "\n")

        return """
        You are the personal finance assistant inside the finAInce app.
        Help the user understand spending, identify patterns, and build healthier financial habits.

        ## Behavior rules
        - Reply in the user's preferred app language: \(responseLanguageInstruction()).
        - Be empathetic and never judge spending habits.
        - Keep responses short: at most 3 short paragraphs or one concise list.
        - Interpret the data instead of repeating raw numbers without context.
        - When relevant, suggest where the user may be able to save money.

        ## Time context (critical)
        - Today's date is: \(now.formatted(.dateTime.day().month(.wide).year()))
        - Current month: \(currentMonthName) \(currentYear) (month number: \(currentMonthNumber))
        - When the user says "this month", ALWAYS refer to \(currentMonthName) \(currentYear)
        - When the user says "last month", refer to the previous calendar month relative to this date
        - NEVER assume January or any fixed month unless explicitly stated by the user

        ## Critical output rules
        - Never reveal chain-of-thought, internal reasoning, or analysis steps.
        - Never mention functions, tools, queries, or that you are looking up data.
        - Never start with phrases like "I'll check", "Let me verify", "Analyzing", or similar.
        - Present the results directly, as if you naturally know the user's financial data.
        - If the request is ambiguous or lacks important context such as period, category, or account,
          ask one direct clarification question before answering.

        ## User financial data
        Today: \(now.formatted(.dateTime.day().month(.wide).year()))
        Current month (authoritative): \(currentMonthName) \(currentYear)
        All transactions below already belong to this current month.
        Do not reinterpret or shift the time period.

        Current month expenses — Total: \(brl(total))

        By category:
        \(catLines.isEmpty ? "No expenses recorded." : catLines)

        Recent transactions:
        \(txLines.isEmpty ? "No expenses recorded." : txLines)
        """
    }

    // MARK: - Gemini

    private static func sendGemini(
        messages: [ChatMessage],
        model: String,
        apiKey: String,
        system: String,
        imageData: Data? = nil
    ) async throws -> String {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw AIError.invalidResponse }

        let lastIndex = messages.indices.last
        let contents: [[String: Any]] = messages.enumerated().map { (i, msg) in
            let role = msg.role == .user ? "user" : "model"
            var parts: [[String: Any]] = [["text": msg.content]]

            // Attach image to last user message
            if i == lastIndex, msg.role == .user, let data = imageData {
                parts.append([
                    "inline_data": [
                        "mime_type": "image/jpeg",
                        "data": data.base64EncodedString()
                    ]
                ])
            }
            return ["role": role, "parts": parts]
        }

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": contents,
            "generationConfig": ["maxOutputTokens": 2048]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = extractErrorMessage(from: data) ?? "Status \(http.statusCode)"
            throw AIError.apiError("Gemini: \(detail)")
        }

        guard
            let json       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let first      = candidates.first,
            let content    = first["content"] as? [String: Any],
            let parts      = content["parts"] as? [[String: Any]],
            let text       = parts.first?["text"] as? String
        else { throw AIError.invalidResponse }

        return text
    }

    // MARK: - OpenAI-compatible (OpenAI + DeepSeek)

    private static func sendOpenAICompatible(
        messages: [ChatMessage],
        model: String,
        apiKey: String,
        system: String,
        baseURL: String,
        providerName: String,
        imageData: Data? = nil
    ) async throws -> String {
        guard let url = URL(string: baseURL) else { throw AIError.invalidResponse }

        // System message is always plain text
        var msgs: [[String: Any]] = [["role": "system", "content": system]]

        let lastIndex = messages.indices.last
        for (i, msg) in messages.enumerated() {
            if i == lastIndex, msg.role == .user, let data = imageData {
                // Multimodal content: text + image for the last user message
                let content: [[String: Any]] = [
                    ["type": "text", "text": msg.content],
                    ["type": "image_url",
                     "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]]
                ]
                msgs.append(["role": "user", "content": content])
            } else {
                msgs.append(["role": msg.role.rawValue, "content": msg.content])
            }
        }

        let body: [String: Any] = [
            "model": model,
            "messages": msgs,
            "max_tokens": 4096
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = extractErrorMessage(from: data) ?? "Status \(http.statusCode)"
            throw AIError.apiError("\(providerName): \(detail)")
        }

        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first   = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw AIError.invalidResponse }

        return content
    }

    // MARK: - Anthropic

    private static func sendAnthropic(
        messages: [ChatMessage],
        model: String,
        apiKey: String,
        system: String,
        imageData: Data? = nil
    ) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIError.invalidResponse
        }

        let lastIndex = messages.indices.last
        let msgs: [[String: Any]] = messages.enumerated().map { (i, msg) in
            if i == lastIndex, msg.role == .user, let data = imageData {
                // Anthropic vision: image first, then text
                let content: [[String: Any]] = [
                    ["type": "image",
                     "source": [
                         "type": "base64",
                         "media_type": "image/jpeg",
                         "data": data.base64EncodedString()
                     ]],
                    ["type": "text", "text": msg.content]
                ]
                return ["role": "user", "content": content]
            }
            return ["role": msg.role.rawValue, "content": msg.content]
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": system,
            "messages": msgs
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey,              forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",        forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = extractErrorMessage(from: data) ?? "Status \(http.statusCode)"
            throw AIError.apiError("Claude: \(detail)")
        }

        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first   = content.first,
            let text    = first["text"] as? String
        else { throw AIError.invalidResponse }

        return text
    }

    // MARK: - Cohere

    private static func sendCohere(
        messages: [ChatMessage],
        model: String,
        apiKey: String,
        system: String
    ) async throws -> String {
        let raw = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        return try await sendRawCohere(raw, model: model, apiKey: apiKey, system: system)
    }

    // MARK: - Receipt Analysis

    struct ReceiptResult {
        let isReceipt: Bool       // true only when the text is clearly a purchase receipt/invoice
        let amount: Double
        let storeName: String
        let suggestedCategorySystemKey: String?
        let suggestedCategoryName: String
        let notes: String
        let date: Date?
    }

    struct ReceiptCategoryOption: Sendable {
        let categorySystemKey: String?
        let categoryName: String
        let categoryDisplayName: String
    }

    struct CategorySuggestionOption: Sendable {
        let categorySystemKey: String?
        let categoryName: String
        let categoryDisplayName: String
        let subcategorySystemKey: String?
        let subcategoryName: String?
        let subcategoryDisplayName: String?
    }

    struct CategorySuggestionResult: Sendable {
        let categorySystemKey: String?
        let categoryName: String
        let subcategorySystemKey: String?
        let subcategoryName: String?
        /// Nome limpo do estabelecimento extraído pela IA da descrição bruta do extrato.
        /// Pode ser nil se a IA não conseguir identificar ou se a entrada já for um nome limpo.
        let resolvedMerchantName: String?
    }

    // Keep this list global and structural. Avoid country-specific banking vocabulary here,
    // otherwise the local heuristic becomes brittle outside a small set of markets.
    // Future expansion point: add only broadly recurring payment/channel words that appear
    // across markets and providers. Avoid city names, country codes, or bank-specific jargon.
    private static let merchantNoiseTerms: Set<String> = [
        "payment", "purchase", "debit", "credit",
        "online", "pos", "mobile", "card", "transfer",
        "tar", "trx", "txn", "ref", "visa", "mastercard"
    ]

    private static let fallbackPaymentPrefixes: [String] = [
        // English
        "card purchase", "debit purchase", "online purchase", "payment", "purchase", "transfer",
        // Portuguese
        "compra no cartao", "compra no cartão", "compra cartao", "compra cartão", "pagamento", "compra", "transferencia", "transferência", "pix",
        // Spanish
        "compra con tarjeta", "pago movil", "pago móvil", "pago", "compra", "transferencia"
    ]

    private static let fallbackLeadingConnectors: Set<String> = [
        "at", "in", "on", "en", "de"
    ]

    private static let merchantCorporateSuffixes: Set<String> = [
        "bv", "b.v", "eu", "sarl", "llc", "ltd", "inc", "gmbh", "sa", "s.a", "sl", "s.l", "plc"
    ]

    static func prepareMerchantTextForAI(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let uppercased = trimmed.uppercased()
        let separators = CharacterSet(charactersIn: ",;|/\\()[]{}")
        let rawSegments = uppercased.components(separatedBy: separators)

        var cleanedSegments: [String] = []
        for segment in rawSegments {
            let words = segment
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .filter { word in
                    let lowered = word.lowercased()
                    if merchantNoiseTerms.contains(lowered) { return false }
                    if lowered.rangeOfCharacter(from: .decimalDigits) != nil { return false }
                    if lowered.count <= 1 { return false }
                    return true
                }

            let rebuilt = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !rebuilt.isEmpty {
                cleanedSegments.append(rebuilt)
            }
        }

        let candidate = cleanedSegments.first(where: { $0.rangeOfCharacter(from: .letters) != nil })
            ?? uppercased
        return candidate.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    static func normalizeMerchantDisplayName(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var sanitized = trimmed
            .replacingOccurrences(of: "[0-9]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[_#*]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.contains(".") {
            let dotParts = sanitized
                .split(separator: ".")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !dotParts.isEmpty {
                sanitized = dotParts.joined(separator: " ")
            }
        }

        var tokens = sanitized
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        while let first = tokens.first, merchantNoiseTerms.contains(first.lowercased()) {
            tokens.removeFirst()
        }
        while let last = tokens.last, merchantCorporateSuffixes.contains(last.lowercased()) {
            tokens.removeLast()
        }

        guard !tokens.isEmpty else { return nil }

        let normalized = tokens
            .map { $0.lowercased().capitalized }
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let validated = validatedMerchantDisplayName(from: normalized, rawValue: trimmed) {
            return validated
        }

        return fallbackMerchantDisplayName(from: trimmed)
    }

    private static func validatedMerchantDisplayName(from candidate: String, rawValue: String) -> String? {
        let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let hasLetters = cleaned.rangeOfCharacter(from: .letters) != nil
        guard hasLetters, cleaned.count >= 3 else { return nil }

        let normalizedRaw = rawValue
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[0-9]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[_#*]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCandidate = cleaned
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[0-9]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateLooksLikeRaw = normalizedCandidate == normalizedRaw

        return candidateLooksLikeRaw ? nil : cleaned
    }

    static func fallbackMerchantDisplayName(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var working = trimmed
            .folding(options: [.diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[0-9]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\b[x*]{2,}[0-9]*\\b", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[_#*]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[,;|/\\\\()\\[\\]{}]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for prefix in fallbackPaymentPrefixes.sorted(by: { $0.count > $1.count }) {
            if working.hasPrefix(prefix + " ") {
                working.removeFirst(prefix.count)
                working = working.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        var tokens = working
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        while let first = tokens.first, fallbackLeadingConnectors.contains(first) {
            tokens.removeFirst()
        }

        tokens = tokens.filter { token in
            let lower = token.lowercased()
            if merchantNoiseTerms.contains(lower) { return false }
            if merchantCorporateSuffixes.contains(lower) { return false }
            if lower.rangeOfCharacter(from: .decimalDigits) != nil { return false }
            if lower.count <= 1 { return false }
            return true
        }

        while let last = tokens.last, merchantCorporateSuffixes.contains(last.lowercased()) {
            tokens.removeLast()
        }

        guard !tokens.isEmpty else { return nil }

        let fallback = tokens
            .map { $0.lowercased().capitalized }
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return fallback.isEmpty ? nil : fallback
    }

    // TODO: Improve accuracy further by adding lightweight pre-cleaning of transaction strings
    // before sending to the AI (remove numbers, card patterns, etc.)
    /// Sugere uma categoria para um estabelecimento quando não há histórico local suficiente.
    static func suggestCategory(
        merchantName: String,
        settings: AISettings,
        options: [CategorySuggestionOption]
    ) async throws -> CategorySuggestionResult? {
        let merchant = prepareMerchantTextForAI(merchantName)
        guard !merchant.isEmpty, !options.isEmpty else { return nil }

        print("🤖 [AI] INICIO DA BUSCA PELA CATEGORIA")
        
        let optionsText = options.map { option in
            if let subcategoryDisplayName = option.subcategoryDisplayName, !subcategoryDisplayName.isEmpty {
                return "- category_key=\(option.categorySystemKey ?? "") | category_label=\(option.categoryDisplayName) | subcategory_key=\(option.subcategorySystemKey ?? "") | subcategory_label=\(subcategoryDisplayName)"
            }
            return "- category_key=\(option.categorySystemKey ?? "") | category_label=\(option.categoryDisplayName)"
        }.joined(separator: "\n")

        let system = """
        You are a global bank transaction categorization engine for a personal finance app.

        \(merchantLanguageInstruction())

        ---

        STEP 1 — EXTRACT MERCHANT NAME

        Raw bank statement strings contain noise. Strip everything that is not the brand/business name:
        - Payment words: PIX, BOLETO, FATURA, PAGAMENTO, PAYMENT, BIZUM, TRANSFERENCIA
        - Transaction type: COMPRA, PURCHASE, DEBIT, CREDIT, DÉBITO, CRÉDITO
        - Channel: POS, ONLINE, MOBILE, CARD, TERMINAL, ATM
        - Location noise: city names, country codes, region codes
        - Number noise: digit sequences, masked cards (XXXX, ****), timestamps
        - Corporate suffixes: SL, SA, BV, SARL, LTD, LTDA, INC, GMBH, S.A., S.L.
        - Generic connectors: AT, EN, IN, DE, COM, NET

        Keep ONLY the actual business or brand name. Output in Title Case — never ALL CAPS.

        Cleaning examples:
        - "PAGO MOVIL EN ADENTIS ALCOBEN, ALCOBENDAS ES" → "Adentis"
        - "UBER BV AMSTERDAM NL" → "Uber"
        - "UBER EATS 800-253-9377" → "Uber Eats"
        - "AMAZON EU SARL LU" → "Amazon"
        - "AMZN MKTP US 123456789" → "Amazon"
        - "NETFLIX.COM 866-579-7172 CA" → "Netflix"
        - "COMPRA PIX IFOOD*RESTAURANTE SABOR" → "iFood"
        - "POS MERCADONA 00123 MADRID" → "Mercadona"
        - "SPOTIFY AB STOCKHOLM" → "Spotify"
        - "GLOVO DELIVERY BCN" → "Glovo"
        - "MCN*MCDONALDS 12345" → "McDonald's"
        - "SHELL SERVICE STATION 001" → "Shell"

        ---

        STEP 2 — CLASSIFY

        Use ONLY the category_key and subcategory_key values from the provided list. Never invent keys.

        GROCERIES (category_key: groceries)
          Supermarkets, hypermarkets, grocery chains → subcategory_key: groceries.market
            Brands: Mercadona, Carrefour, Lidl, Aldi, DIA, Eroski, Pão de Açúcar, Extra, Walmart, Tesco, Whole Foods, Kroger, Morrisons, Sainsbury's
          Farmers markets, open-air food markets → groceries.fair
          Butcher shops, meat stores → groceries.butcher
          Bakeries, bread shops, pastry shops → groceries.bakery
          Produce shops, fruit and vegetable stores → groceries.produce

        RESTAURANTS (category_key: restaurants)
          Sit-down restaurants, diners → subcategory_key: restaurants.lunchDinner
          Food delivery apps → restaurants.delivery
            Brands: iFood, Uber Eats, Glovo, Rappi, DoorDash, Deliveroo, Just Eat, Pedidos Ya
          Fast food chains → restaurants.fastFood
            Brands: McDonald's, Burger King, KFC, Subway, Domino's, Pizza Hut, Wendy's, Five Guys, Popeyes
          Coffee shops, cafés, snack bars → restaurants.coffeeSnack
            Brands: Starbucks, Costa Coffee, Tim Hortons, Nespresso, Dunkin', Bob's Coffee
          Bars, pubs, breweries → restaurants.bars

        TRANSPORT (category_key: transport)
          Gas/petrol stations → subcategory_key: transport.fuel
            Brands: Shell, BP, Repsol, Petrobras, Ipiranga, Cepsa, Total, Galp, Esso, Chevron
          Parking lots, garages → transport.parking
          Bus, subway, metro, commuter rail → transport.publicTransit
            Brands: RENFE, SNCF, DB Bahn, CPTM, Metrô SP, Transporte Madrid, STCP, TfL, BART
          Ride-hailing apps (rides, not food) → transport.rideHailing
            Brands: Uber (rides), Lyft, Cabify, 99, InDriver, DiDi, Bolt rides
          Car maintenance, tire shops, mechanics → transport.maintenance
          Toll roads, highway fees → transport.tolls
          ⚠️ "Uber" alone → transport.rideHailing. "Uber Eats" → restaurants.delivery.
          ⚠️ "Bolt" for scooters/rides → transport.rideHailing. "Bolt" for food → restaurants.delivery.

        HEALTH (category_key: health)
          Health insurance, medical plans → subcategory_key: health.insurance
          Doctors, clinics, hospitals → health.consultation
          Pharmacies, drugstores → health.pharmacy
            Brands: Farmácia São João, Droga Raia, Ultrafarma, CVS, Boots, Farmacia Guadalajara
          Lab tests, diagnostics → health.tests
          Dentists, dental clinics → health.dentist

        TRAVEL (category_key: travel)
          Airlines, flight bookings → subcategory_key: travel.tickets
            Brands: TAM, GOL, Azul, Iberia, Ryanair, EasyJet, LATAM, Vueling, TAP, British Airways, Delta
          Hotels, hostels, short-term rentals → travel.lodging
            Brands: Airbnb, Booking.com, Expedia, Hotels.com, NH Hotels, Marriott, Hilton
          Tours, excursions → travel.tours
          Car rental agencies → travel.carRental
            Brands: Hertz, Avis, Europcar, Sixt, Localiza, Unidas, Enterprise

        EDUCATION (category_key: education)
          Schools, universities, tutoring centers → subcategory_key: education.school
          Online course platforms → education.courses
            Brands: Coursera, Udemy, Duolingo, Skillshare, LinkedIn Learning, Alura, Hotmart
          Bookstores → education.books
          School supplies stores → education.supplies

        LEISURE (category_key: leisure)
          Cinemas, theaters, concerts, event tickets → subcategory_key: leisure.moviesShows
            Brands: Cinemark, Cinépolis, Odeon, UCI, Ticketmaster, Ingresso.com
          Hobbies, arts and crafts → leisure.hobbies
          Video game purchases (one-time, not subscriptions) → leisure.games

        SHOPPING (category_key: shopping)
          Clothing and apparel → subcategory_key: shopping.clothes
            Brands: Zara, H&M, Mango, Renner, C&A, Shein, Pull&Bear, Bershka, Stradivarius, Primark
          Footwear → shopping.shoes
            Brands: Nike, Adidas, Arezzo, Schutz, Vans, Converse, Foot Locker
          Accessories, jewelry → shopping.accessories
          Gifts, general retail, department stores → shopping.gifts
            Brands: El Corte Inglés, Americanas, Casas Bahia
          ⚠️ Amazon marketplace order → shopping. Amazon Prime subscription → subscriptions.saas.
          ⚠️ Apple hardware/App Store purchase → shopping. Apple iCloud → subscriptions.cloudBackup. Apple TV+ → subscriptions.streaming.

        PETS (category_key: pets)
          Pet food and supplies stores → subcategory_key: pets.store
            Brands: Petco, Cobasi, Petz, Zooplus, Animalis
          Veterinary clinics → pets.vet
          Pet grooming services → pets.grooming

        PERSONAL CARE (category_key: personalCare)
          Hair salons, barbershops, beauty salons → subcategory_key: personalCare.hairBeauty
          Hygiene product stores → personalCare.hygiene
          Cosmetics and perfumeries → personalCare.cosmetics
            Brands: Sephora, O Boticário, Natura, L'Occitane, Douglas, Primor

        FINANCIAL (category_key: financial)
          Bank fees, account maintenance charges → subcategory_key: financial.bankFees
          Insurance (life, home, non-health) → financial.insurance
          Loan repayments → financial.loan
          Government taxes, fees → financial.taxes
          Interest charges → financial.interestFees

        SUBSCRIPTIONS (category_key: subscriptions)
          Video streaming → subcategory_key: subscriptions.streaming
            Brands: Netflix, Disney+, HBO Max, Amazon Prime Video, Apple TV+, Paramount+, Peacock, Globoplay
          Music streaming → subscriptions.music
            Brands: Spotify, Apple Music, Deezer, Tidal, Amazon Music, YouTube Music
          Cloud storage → subscriptions.cloudBackup
            Brands: iCloud, Google One, Dropbox, OneDrive, Backblaze
          Software/SaaS → subscriptions.saas
            Brands: Adobe, Microsoft 365, Notion, Slack, Figma, Canva, GitHub, 1Password, NordVPN
          Mobile apps, App Store, Google Play → subscriptions.apps
          Game subscriptions → subscriptions.games
            Brands: Xbox Game Pass, PlayStation Plus, EA Play, Nintendo Online

        SPORTS (category_key: sports)
          Gyms, fitness centers, CrossFit boxes → subcategory_key: sports.gym
            Brands: SmartFit, Bodytech, Planet Fitness, Holmes Place, FitLife, Anytime Fitness
          Running events, race registrations → sports.running
          Sports equipment and multi-sport retailers → sports.general
            Brands: Decathlon, Nike (equipment), Adidas (equipment), Sport Zone
          Swimming pools, aquatic centers → sports.swimming

        HOUSING (category_key: housing)
          Rent payments → subcategory_key: housing.rent
          Mortgage / home loan → housing.mortgage
          Condo/HOA fees → housing.condo
          Electricity/power utilities → housing.energy
          Water utility → housing.water
          Gas utility (home) → housing.gas
          Internet service provider → housing.internet
          Mobile phone plan → housing.phone
          Cable TV, satellite → housing.tvStreaming
          Property tax → housing.propertyTax

        OTHER (category_key: other)
          Charities, NGOs, donations → subcategory_key: other.donations
          Clearly gift-oriented stores → other.gifts
          Truly unclassifiable → other.misc

        ---

        CONFIDENCE:
        - 90–100: well-known brand with clear category (Spotify → subscriptions.music, Mercadona → groceries.market)
        - 75–89: merchant type is clear even if brand is unknown (pharmacy → health.pharmacy)
        - below 70: genuinely ambiguous or too noisy — return empty strings for category_key and subcategory_key

        ---

        OUTPUT: Return ONLY valid JSON. No markdown. No explanation.

        {
          "merchant": string,
          "category_key": string,
          "subcategory_key": string,
          "confidence": number
        }
        """

        let user = """
        Statement: \(merchant)

        Categories:
        \(optionsText)
        """

        // Apple Intelligence (on-device): two-step plain-text approach.
        // Step 1 — pick root category from a short list.
        // Step 2 — if a root was found, pick subcategory from its children.
        // Asking for a single word from a short list is much more reliable than JSON.
        if settings.provider == .local {
            return try? await suggestCategoryLocal(merchant: merchant, options: options)
        }

        guard let apiKey = KeychainHelper.load(forKey: settings.provider.keychainKey),
              !apiKey.isEmpty else {
            throw AIError.noAPIKey
        }

        let raw: [[String: String]] = [["role": "user", "content": user]]
        let responseText: String
        switch settings.provider {
        case .local:
            fatalError("handled above")
        case .groq:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.groq.com/openai/v1/chat/completions"
            )
        case .deepseek:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.deepseek.com/v1/chat/completions"
            )
        case .openai:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.openai.com/v1/chat/completions"
            )
        case .gemini:
            responseText = try await sendRawGemini(
                raw, model: settings.model, apiKey: apiKey, system: system
            )
        case .anthropic:
            responseText = try await sendRawAnthropic(
                raw, model: settings.model, apiKey: apiKey, system: system
            )
        case .openrouter:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://openrouter.ai/api/v1/chat/completions"
            )
        case .cerebras:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.cerebras.ai/v1/chat/completions"
            )
        case .huggingface:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://router.huggingface.co/v1/chat/completions"
            )
        case .mistral:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.mistral.ai/v1/chat/completions"
            )
        case .cohere:
            responseText = try await sendRawCohere(
                raw, model: settings.model, apiKey: apiKey, system: system
            )
        }

        let clean = responseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        print("🤖 [AI Category] raw response: \(responseText)")
        print("🤖 [AI Category] cleaned     : \(clean)")
        #endif

        guard
            let jsonText = extractFirstJSONObjectString(from: clean) ?? extractFirstJSONObjectString(from: responseText),
            let data = jsonText.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            #if DEBUG
            print("🤖 [AI Category] ❌ JSON parse failed for: \(clean)")
            #endif
            throw AIError.invalidResponse
        }

        let categorySystemKey = ((json["category_key"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let subcategorySystemKey = ((json["subcategory_key"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let merchantName = normalizeMerchantDisplayName((json["merchant"] as? String) ?? "")
        let confidence      = (json["confidence"]  as? Int)    ?? 100  // default high if omitted

        #if DEBUG
        print("🤖 [AI Category] confidence: \(confidence)%")
        #endif

        guard !categorySystemKey.isEmpty else {
            return fallbackOtherCategoryResult(from: options, resolvedMerchantName: merchantName)
        }

        let selectedOption = options.first {
            $0.categorySystemKey == categorySystemKey && (
                ($0.subcategorySystemKey ?? "") == subcategorySystemKey
                || ($0.subcategorySystemKey == nil && subcategorySystemKey.isEmpty)
            )
        } ?? options.first {
            $0.categorySystemKey == categorySystemKey && $0.subcategorySystemKey == nil
        }

        guard let selectedCategory = selectedOption ?? options.first(where: { $0.categorySystemKey == categorySystemKey }) else {
            return fallbackOtherCategoryResult(from: options, resolvedMerchantName: merchantName)
        }

        // Below 70 % confidence → fall back to "Outros" if it exists in the list, else nil
        if confidence < 70 {
            #if DEBUG
            print("🤖 [AI Category] ⚠️ confidence \(confidence)% < 70 — falling back to Outros")
            #endif
            let outros = options.first {
                $0.categorySystemKey == DefaultCategories.otherCategorySystemKey
            }
            guard let outros else { return nil }
            return CategorySuggestionResult(
                categorySystemKey:    outros.categorySystemKey,
                categoryName:         outros.categoryName,
                subcategorySystemKey: nil,
                subcategoryName:      nil,
                resolvedMerchantName: merchantName
            )
        }

        return CategorySuggestionResult(
            categorySystemKey:    selectedCategory.categorySystemKey,
            categoryName:         selectedCategory.categoryName,
            subcategorySystemKey: selectedOption?.subcategorySystemKey,
            subcategoryName:      selectedOption?.subcategoryName,
            resolvedMerchantName: merchantName
        )
    }

    // MARK: - Spending Insight

    /// Generates a 1–2 sentence spending insight for the charts view.
    static func generateSpendingInsight(
        monthName: String,
        currentDay: Int,
        daysInMonth: Int,
        currentTotal: Double,
        prevTotal: Double,
        topCategory: String?,
        topMerchant: String?,
        currencyCode: String,
        settings: AISettings
    ) async throws -> String {
        let pct: Int = {
            guard prevTotal > 0 else { return 0 }
            return Int(((currentTotal - prevTotal) / prevTotal * 100).rounded())
        }()
        let estimated = currentDay > 0
            ? (currentTotal / Double(currentDay)) * Double(daysInMonth)
            : currentTotal
        let fmt: (Double) -> String = { v in
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = currencyCode
            f.maximumFractionDigits = 2
            return f.string(from: NSNumber(value: v)) ?? "\(v)"
        }
        let trendLabel = pct >= 0 ? "+\(pct)%" : "\(pct)%"

        let system = """
        You are a personal finance advisor. Reply in the user's preferred app language: \(responseLanguageInstruction()).
        Be direct and practical. Use 1 or 2 sentences maximum. No greetings. No markdown.
        """
        let user = """
        Spending summary — \(monthName):
        • Day \(currentDay) of \(daysInMonth)
        • Spent so far: \(fmt(currentTotal)) (\(trendLabel) vs same period last month, which was \(fmt(prevTotal)))
        • Estimated month-end total at current pace: \(fmt(estimated))
        • Top spending category: \(topCategory ?? "N/A")
        • Top merchant: \(topMerchant ?? "N/A")

        Give ONE concise, actionable insight about the spending trend.
        """

        if settings.provider == .local {
            let result = await LocalAIService.generate(prompt: "\(system)\n\n\(user)")
            return result ?? ""
        }

        guard let apiKey = KeychainHelper.load(forKey: settings.provider.keychainKey),
              !apiKey.isEmpty else { throw AIError.noAPIKey }

        let raw: [[String: String]] = [["role": "user", "content": user]]
        let responseText: String
        switch settings.provider {
        case .local: fatalError("handled above")
        case .groq:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.groq.com/openai/v1/chat/completions")
        case .deepseek:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.deepseek.com/v1/chat/completions")
        case .openai:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.openai.com/v1/chat/completions")
        case .gemini:
            responseText = try await sendRawGemini(
                raw, model: settings.model, apiKey: apiKey, system: system)
        case .anthropic:
            responseText = try await sendRawAnthropic(
                raw, model: settings.model, apiKey: apiKey, system: system)
        case .openrouter:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://openrouter.ai/api/v1/chat/completions")
        case .cerebras:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.cerebras.ai/v1/chat/completions")
        case .huggingface:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://router.huggingface.co/v1/chat/completions")
        case .mistral:
            responseText = try await sendRawOpenAICompatible(
                raw, model: settings.model, apiKey: apiKey, system: system,
                baseURL: "https://api.mistral.ai/v1/chat/completions")
        case .cohere:
            responseText = try await sendRawCohere(
                raw, model: settings.model, apiKey: apiKey, system: system)
        }
        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Two-step local categorisation (Apple Intelligence)

    /// Asks Apple Intelligence two short plain-text questions instead of requesting JSON.
    /// Step 1: pick a root category from the user's list.
    /// Step 2: if a root was matched, pick a subcategory from its children.
    private static func suggestCategoryLocal(
        merchant: String,
        options: [CategorySuggestionOption]
    ) async throws -> CategorySuggestionResult? {
        let normalizedMerchant = normalizeMerchantDisplayName(merchant)

        // Deduplicate root categories preserving order
        var seen = Set<String>()
        let rootOptions: [CategorySuggestionOption] = options.compactMap { option in
            guard option.subcategorySystemKey == nil else { return nil }
            let uniqueKey = option.categorySystemKey ?? option.categoryName
            return seen.insert(uniqueKey).inserted ? option : nil
        }

        // ── Step 1: root category + confidence ──────────────────────────────
        // For custom categories (no systemKey), use lowercased name as identifier
        let validRootOptions = rootOptions.map { option -> CategorySuggestionOption in
            if (option.categorySystemKey ?? "").isEmpty {
                return CategorySuggestionOption(
                    categorySystemKey: option.categoryName.lowercased().replacingOccurrences(of: " ", with: "_"),
                    categoryName: option.categoryName,
                    categoryDisplayName: option.categoryDisplayName,
                    subcategorySystemKey: nil,
                    subcategoryName: nil,
                    subcategoryDisplayName: nil
                )
            }
            return option
        }

        let step1 = """
        \(merchantLanguageInstruction())

        Merchant name: "\(normalizedMerchant ?? merchant)"

        Step 1 — What TYPE of business is this? (cinema, pharmacy, supermarket, gym, etc.)
        Step 2 — Match that type to the best category_key below.

        Type → category_key reference:
        cinema/theatre/show/concert/museum/park/zoo → leisure
        restaurant/cafe/bar/delivery/fast food/pub → restaurants
        supermarket/grocery/bakery/butcher/market → groceries
        pharmacy/clinic/hospital/dentist/lab → health
        gym/fitness/sport/swimming/running → sports
        fuel/taxi/bus/metro/parking/toll/airline → transport
        hotel/hostel/airbnb/tour/car rental → travel
        streaming/music/cloud/saas/app subscription → subscriptions
        clothing/shoes/mall/retail/accessories → shopping
        school/university/course/bookstore → education
        rent/utility/electricity/water/internet/phone → housing
        bank fee/insurance/loan/tax → financial
        salon/barber/spa/cosmetics → personalCare
        pet store/vet/grooming → pets

        Available category keys:
        \(validRootOptions.map { "\($0.categorySystemKey ?? $0.categoryName) → \($0.categoryDisplayName)" }.joined(separator: "\n"))

        Reply ONLY in this exact format (no extra text):
        CATEGORY_KEY|CONFIDENCE|reason
        Example: leisure|90|Cinemark is a cinema chain
        If truly unknown, reply: other|50|unknown merchant
        """

        #if DEBUG
        print("🤖 [AI/local step1] prompt: \(step1)")
        #endif

        guard let rawStep1 = await LocalAIService.classify(prompt: step1), !rawStep1.isEmpty else {
            return fallbackOtherCategoryResult(from: options, resolvedMerchantName: normalizedMerchant)
        }

        #if DEBUG
        print("🤖 [AI/local step1] response: '\(rawStep1)'")
        #endif

        // Parse "CATEGORY_KEY|CONFIDENCE|Reasoning" — split all parts so confidence index is always [1]
        let step1Parts = rawStep1.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let rawRoot    = step1Parts[0]
        let localConf  = step1Parts.count > 1 ? Int(step1Parts[1]) ?? 100 : 100

        let fold: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        let foldedRoot = fold(rawRoot)
        guard !foldedRoot.isEmpty else {
            return fallbackOtherCategoryResult(from: options, resolvedMerchantName: normalizedMerchant)
        }

        let matchedRoot = validRootOptions.first { fold($0.categorySystemKey ?? "") == foldedRoot }
            ?? validRootOptions.first { fold($0.categorySystemKey ?? "").contains(foldedRoot) || foldedRoot.contains(fold($0.categorySystemKey ?? "")) }
            ?? validRootOptions.first { fold($0.categoryDisplayName) == foldedRoot || fold($0.categoryName) == foldedRoot }

        guard let matchedRoot else {
            #if DEBUG
            print("🤖 [AI/local step1] ❌ '\(rawRoot)' not found in [\(validRootOptions.compactMap(\.categorySystemKey).joined(separator: ", "))]")
            #endif
            return fallbackOtherCategoryResult(from: options, resolvedMerchantName: normalizedMerchant)
        }

        #if DEBUG
            print("🤖 [AI/local step1] ✅ matched root: '\(matchedRoot.categorySystemKey ?? matchedRoot.categoryName)' confidence: \(localConf)%")
        #endif

        // Below 70 % → fall back to "Outros" if available, else nil
        if localConf < 70 {
            #if DEBUG
            print("🤖 [AI/local step1] ⚠️ confidence \(localConf)% < 70 — falling back to Outros")
            #endif
            let outros = rootOptions.first { $0.categorySystemKey == DefaultCategories.otherCategorySystemKey }
            return CategorySuggestionResult(
                categorySystemKey:    (outros ?? matchedRoot).categorySystemKey,
                categoryName:         (outros ?? matchedRoot).categoryName,
                subcategorySystemKey: nil,
                subcategoryName:      nil,
                resolvedMerchantName: normalizedMerchant
            )
        }
        // ── Step 2: subcategory (only if children exist) ─────────────────────
        let subOptions = options.filter {
            $0.categorySystemKey == matchedRoot.categorySystemKey && $0.subcategorySystemKey != nil
        }

        var matchedSub: CategorySuggestionOption? = nil

        if !subOptions.isEmpty {
            let step2 = """
            Merchant: "\(merchant)" (category: \(matchedRoot.categoryDisplayName))
            Subcategories:
            \(subOptions.map { "key=\($0.subcategorySystemKey ?? "") | label=\($0.subcategoryDisplayName ?? "")" }.joined(separator: "\n"))

            Which subcategory_key best fits this merchant?
            Reply with only the key (e.g. "restaurants.fastFood"). If none fits, reply with nothing.
            """

            #if DEBUG
            print("🤖 [AI/local step2] prompt: \(step2)")
            #endif

            if let rawSub = await LocalAIService.classify(prompt: step2), !rawSub.isEmpty {
                #if DEBUG
                print("🤖 [AI/local step2] response: '\(rawSub)'")
                #endif
                let foldedSub = fold(rawSub)
                matchedSub = subOptions.first { fold($0.subcategorySystemKey ?? "") == foldedSub }
                    ?? subOptions.first { fold($0.subcategorySystemKey ?? "").contains(foldedSub) || foldedSub.contains(fold($0.subcategorySystemKey ?? "")) }
                #if DEBUG
                print("🤖 [AI/local step2] matched sub: '\(matchedSub?.subcategorySystemKey ?? "none")'")
                #endif
            }
        }

        return CategorySuggestionResult(
            categorySystemKey:    matchedRoot.categorySystemKey,
            categoryName:         matchedRoot.categoryName,
            subcategorySystemKey: matchedSub?.subcategorySystemKey,
            subcategoryName:      matchedSub?.subcategoryName,
            resolvedMerchantName: normalizedMerchant
        )
    }

    private static func fallbackOtherCategoryResult(
        from options: [CategorySuggestionOption],
        resolvedMerchantName: String?
    ) -> CategorySuggestionResult? {
        guard let other = options.first(where: { $0.categorySystemKey == DefaultCategories.otherCategorySystemKey }) else {
            return nil
        }

        return CategorySuggestionResult(
            categorySystemKey: other.categorySystemKey,
            categoryName: other.categoryName,
            subcategorySystemKey: nil,
            subcategoryName: nil,
            resolvedMerchantName: resolvedMerchantName
        )
    }

    /// Analisa texto extraído via OCR de um recibo e retorna valor, estabelecimento, categoria sugerida e observação.
    static func analyzeReceipt(
        ocrText: String,
        settings: AISettings,
        categoryOptions: [ReceiptCategoryOption] = []
    ) async throws -> ReceiptResult {

        let userLang = LanguageManager.shared.effective.rawValue

        let categoriesHint = categoryOptions.isEmpty
            ? ""
            : "\n\nAvailable categories (choose the best match):\n\(categoryOptions.map { "- category_key=\($0.categorySystemKey ?? "") | label=\($0.categoryDisplayName)" }.joined(separator: "\n"))"

        let system = """
        You are a financial receipt extractor for a personal finance app.
        The user's language is \(userLang).

        YOUR ONLY JOB: determine if the text is a purchase receipt/invoice and, if so, extract structured data.

        RECEIPT DETECTION RULES:
        - A receipt/invoice must have: a merchant/store name AND a total amount paid.
        - Bank statements, screenshots, menus without totals, chat messages, photos without purchase context → NOT a receipt.
        - If uncertain, set "is_receipt": false.

        AMOUNT RULES (critical):
        - Always extract the FINAL TOTAL the customer paid (after discounts, taxes, tips).
        - Prefer fields labeled: Total, Total Pago, Valor Total, Grand Total, Amount Due, Importe Total.
        - NEVER use: Subtotal, Sub-total, Partial, Parcial, Tax alone, Tip alone.
        - If multiple totals exist (split bill, installments), use the largest single-payment amount.
        - Strip currency symbols (R$, $, €, £, ¥) — return only the numeric value.
        - Use decimal dot (not comma): R$ 1.234,56 → 1234.56

        DATE RULES:
        - Return purchase date in yyyy-MM-dd format.
        - If only time is shown without date, return empty string.
        - Common formats: DD/MM/YYYY, MM/DD/YYYY, YYYY-MM-DD — parse all correctly.

        OUTPUT: Return ONLY a single valid JSON object. No markdown, no explanation, no extra text.
        """

        let user = """
        Analyze this OCR text and extract receipt data.\(categoriesHint)

        OCR TEXT:
        ---
        \(ocrText)
        ---

        Return this exact JSON:
        {
          "is_receipt": <true if this is clearly a purchase receipt or invoice, false otherwise>,
          "valor": <total amount paid as decimal number, e.g. 42.50, or 0 if not a receipt>,
          "estabelecimento": "<merchant/store name, cleaned up, or empty string>",
          "categoria_key": "<category_key from the list above that best matches, or empty string>",
          "data": "<purchase date as yyyy-MM-dd, or empty string>",
          "observacao": "<one short sentence with the most useful detail, e.g. main item or purpose, or empty string>"
        }
        """

        let responseText: String

        // ── Apple Intelligence (on-device, sem chave de API) ──────────────
        // The on-device model is very small (~3B). Use a minimal prompt so it
        // reliably returns valid JSON instead of ignoring complex instructions.
        if settings.provider == .local {
            let catList = categoryOptions.isEmpty
                ? ""
                : " Categories: \(categoryOptions.prefix(10).map { "\($0.categorySystemKey ?? "")" }.joined(separator: ", "))."

            let localPrompt = """
            Return ONLY valid JSON. No explanation.
            Is this text a purchase receipt? If yes, extract total amount paid, store name, date.
            JSON format: {"is_receipt":true,"valor":0.0,"estabelecimento":"","categoria_key":"","data":"","observacao":""}
            Rules: valor = final total paid (not subtotal, not tax alone). Use decimal dot (e.g. 42.50).\(catList)

            TEXT:
            \(ocrText.prefix(800))
            """

            let emptyContext = FinanceContext(
                transactions: [],
                goals: [],
                accounts: [],
                categories: [],
                currencyCode: CurrencyOption.defaultCode,
                appLanguageCode: LanguageManager.shared.effective.rawValue,
                localeIdentifier: Locale.current.identifier,
                timeZoneIdentifier: TimeZone.current.identifier
            )
            let result = try await LocalAIService.send(
                userMessage: localPrompt,
                context: emptyContext
            )
            responseText = result.content
        } else {
            // ── Provedores cloud ───────────────────────────────────────────
            guard let apiKey = KeychainHelper.load(forKey: settings.provider.keychainKey),
                  !apiKey.isEmpty else {
                throw AIError.noAPIKey
            }

            let raw: [[String: String]] = [["role": "user", "content": user]]

            switch settings.provider {
            case .local:
                fatalError("handled above")
            case .groq:
                responseText = try await sendRawOpenAICompatible(
                    raw, model: settings.model, apiKey: apiKey, system: system,
                    baseURL: "https://api.groq.com/openai/v1/chat/completions"
                )
            case .deepseek:
                responseText = try await sendRawOpenAICompatible(
                    raw, model: settings.model, apiKey: apiKey, system: system,
                    baseURL: "https://api.deepseek.com/v1/chat/completions"
                )
            case .openai:
                responseText = try await sendRawOpenAICompatible(
                    raw, model: settings.model, apiKey: apiKey, system: system,
                    baseURL: "https://api.openai.com/v1/chat/completions"
                )
            case .gemini:
                responseText = try await sendRawGemini(
                    raw, model: settings.model, apiKey: apiKey, system: system
                )
            case .anthropic:
                responseText = try await sendRawAnthropic(
                    raw, model: settings.model, apiKey: apiKey, system: system
                )
            case .openrouter:
                responseText = try await sendRawOpenAICompatible(
                    raw, model: settings.model, apiKey: apiKey, system: system,
                    baseURL: "https://openrouter.ai/api/v1/chat/completions"
                )
            case .cerebras:
                responseText = try await sendRawOpenAICompatible(
                    raw, model: settings.model, apiKey: apiKey, system: system,
                    baseURL: "https://api.cerebras.ai/v1/chat/completions"
                )
            case .huggingface:
                responseText = try await sendRawOpenAICompatible(
                    raw, model: settings.model, apiKey: apiKey, system: system,
                    baseURL: "https://router.huggingface.co/v1/chat/completions"
                )
            case .mistral:
                responseText = try await sendRawOpenAICompatible(
                    raw, model: settings.model, apiKey: apiKey, system: system,
                    baseURL: "https://api.mistral.ai/v1/chat/completions"
                )
            case .cohere:
                responseText = try await sendRawCohere(
                    raw, model: settings.model, apiKey: apiKey, system: system
                )
            }
        }

        // Limpa possível markdown do modelo e faz parse do JSON
        let clean = responseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("📄 [ReceiptAI · \(settings.provider.label)] raw response: \(clean.prefix(300))")

        guard
            let data = clean.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            print("❌ [ReceiptAI · \(settings.provider.label)] JSON parse failed — raw was: \(clean.prefix(300))")
            throw AIError.invalidResponse
        }

        let isReceipt: Bool = {
            if let b = json["is_receipt"] as? Bool { return b }
            if let s = json["is_receipt"] as? String { return s.lowercased() == "true" }
            // Fallback: treat as receipt if amount > 0 and store name present (older model behaviour)
            return false
        }()
        let amount: Double = {
            if let d = json["valor"] as? Double { return d }
            if let i = json["valor"] as? Int    { return Double(i) }
            if let s = json["valor"] as? String {
                // Handle comma-as-decimal (e.g. "1.234,56" → 1234.56)
                let normalized = s
                    .replacingOccurrences(of: ".", with: "")  // remove thousand sep
                    .replacingOccurrences(of: ",", with: ".")  // decimal
                return Double(normalized) ?? Double(s) ?? 0
            }
            return 0
        }()
        let storeName = normalizeMerchantDisplayName((json["estabelecimento"] as? String) ?? "") ?? ""
        let categorySystemKey = ((json["categoria_key"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let matchedCategory = categoryOptions.first { $0.categorySystemKey == categorySystemKey }
        let notes = (json["observacao"] as? String) ?? ""
        let dateString = (json["data"] as? String) ?? ""
        let date = CSVImportService.parseDate(dateString)
        return ReceiptResult(
            isReceipt: isReceipt,
            amount: amount,
            storeName: storeName,
            suggestedCategorySystemKey: matchedCategory?.categorySystemKey,
            suggestedCategoryName: matchedCategory?.categoryName ?? "",
            notes: notes,
            date: date
        )
    }

    // MARK: - Raw message helpers (sem SwiftData, para uso interno)

    private static func sendRawOpenAICompatible(
        _ messages: [[String: String]],
        model: String, apiKey: String, system: String, baseURL: String
    ) async throws -> String {
        guard let url = URL(string: baseURL) else { throw AIError.invalidResponse }

        var msgs: [[String: String]] = [["role": "system", "content": system]]
        msgs += messages

        let body: [String: Any] = ["model": model, "messages": msgs, "max_tokens": 256, "temperature": 0.1]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)",  forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = extractErrorMessage(from: data) ?? "Status \(http.statusCode)"
            throw AIError.apiError(detail)
        }
        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let msg     = choices.first?["message"] as? [String: Any],
            let text    = msg["content"] as? String
        else { throw AIError.invalidResponse }
        return text
    }

    private static func sendRawGemini(
        _ messages: [[String: String]],
        model: String, apiKey: String, system: String
    ) async throws -> String {
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlStr) else { throw AIError.invalidResponse }

        let contents: [[String: Any]] = messages.map { msg in
            ["role": msg["role"] == "user" ? "user" : "model",
             "parts": [["text": msg["content"] ?? ""]]]
        }
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": contents,
            "generationConfig": ["maxOutputTokens": 256]
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = extractErrorMessage(from: data) ?? "Status \(http.statusCode)"
            throw AIError.apiError("Gemini: \(detail)")
        }
        guard
            let json       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content    = candidates.first?["content"] as? [String: Any],
            let parts      = content["parts"] as? [[String: Any]],
            let text       = parts.first?["text"] as? String
        else { throw AIError.invalidResponse }
        return text
    }

    private static func sendRawCohere(
        _ messages: [[String: String]],
        model: String, apiKey: String, system: String
    ) async throws -> String {
        guard let url = URL(string: "https://api.cohere.com/v2/chat") else {
            throw AIError.invalidResponse
        }

        let msgs = messages.map { msg in
            [
                "role": msg["role"] == "assistant" ? "assistant" : "user",
                "content": msg["content"] ?? ""
            ]
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system]] + msgs,
            "max_tokens": 512,
            "temperature": 0.2
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = extractErrorMessage(from: data) ?? "Status \(http.statusCode)"
            throw AIError.apiError("Cohere: \(detail)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse
        }

        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]],
           let text = content.first?["text"] as? String {
            return text
        }

        if let text = json["text"] as? String {
            return text
        }

        throw AIError.invalidResponse
    }

    private static func sendRawAnthropic(
        _ messages: [[String: String]],
        model: String, apiKey: String, system: String
    ) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIError.invalidResponse
        }
        let body: [String: Any] = [
            "model": model, "max_tokens": 256, "system": system, "messages": messages
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = extractErrorMessage(from: data) ?? "Status \(http.statusCode)"
            throw AIError.apiError("Claude: \(detail)")
        }
        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let text    = content.first?["text"] as? String
        else { throw AIError.invalidResponse }
        return text
    }

    // MARK: - Helpers

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // OpenAI / Anthropic: { "error": { "message": "..." } }
        if let error = json["error"] as? [String: Any],
           let msg = error["message"] as? String { return msg }
        // Gemini: { "error": { "message": "..." } } (same shape)
        return nil
    }

    private static func extractFirstJSONObjectString(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.first == "{", trimmed.last == "}" {
            return trimmed
        }

        guard let start = trimmed.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var isEscaping = false

        for index in trimmed.indices[start...] {
            let character = trimmed[index]

            if inString {
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
                continue
            }

            if character == "{" {
                depth += 1
                continue
            }

            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(trimmed[start...index])
                }
            }
        }

        return nil
    }
}

private extension AIService {
    static func responseLanguageInstruction() -> String {
        switch LanguageManager.shared.effective {
        case .ptBR:
            return "Brazilian Portuguese (pt-BR)"
        case .en:
            return "English (en)"
        case .es:
            return "Spanish (es)"
        case .system:
            return "English (en)"
        }
    }

    /// Returns a language-aware context block for merchant categorization prompts.
    /// Tells the AI which language the bank statements are likely in and provides
    /// local vocabulary hints so terms like "Drogaria" or "Farmacia" are recognized.
    static func merchantLanguageInstruction() -> String {
        switch LanguageManager.shared.effective {

        case .ptBR, .system:
            return """
            LANGUAGE CONTEXT:
            The user's app language is Brazilian Portuguese (pt-BR).
            Bank statements are likely in Portuguese. Interpret merchant names using Portuguese business vocabulary and patterns.

            IMPORTANT:
            - Merchant strings may contain noise (numbers, locations, payment types, etc.)
            - Focus only on the business type and brand identity
            - Ignore prefixes like: PIX, PAGAMENTO, COMPRA, TRANSFERENCIA, BOLETO

            KEY CATEGORY MAPPINGS (Portuguese):

            HEALTH (health.*)
            - Farmácia, Drogaria, Droga, Farma → health.pharmacy
            - Clínica, Hospital, UPA, Pronto Socorro, Laboratório → health.consultation
            - Dentista, Odonto → health.dentist

            TRANSPORT (transport.*)
            - Posto, Combustível, Gasolina, Etanol, Diesel → transport.fuel
            - Uber, 99, Cabify → transport.rideHailing
            - Estacionamento, Zona Azul, Parking → transport.parking
            - Pedágio, Sem Parar → transport.tolls
            - Metrô, CPTM, Ônibus, BRT, VLT → transport.publicTransit

            GROCERIES (groceries.*)
            - Mercado, Supermercado, Hipermercado → groceries.market
            - Hortifruti, Sacolão, Feira → groceries.produce
            - Açougue, Frigorífico → groceries.butcher
            - Padaria, Panificadora, Confeitaria → groceries.bakery

            RESTAURANTS (restaurants.*)
            - Restaurante, Lanchonete → restaurants.lunchDinner
            - Ifood, Rappi → restaurants.delivery
            - McDonald's, Burger King → restaurants.fastFood
            - Cafeteria, Café → restaurants.coffeeSnack
            - Bar, Pub → restaurants.bars

            SHOPPING (shopping.*)
            - Loja, Magazine, Shopping → shopping.gifts
            - Roupas, Vestuário → shopping.clothes
            - Calçados, Sapatos → shopping.shoes

            SUBSCRIPTIONS (subscriptions.*)
            - Netflix, Spotify → subscriptions.streaming / subscriptions.music
            - iCloud, Google One → subscriptions.cloudBackup
            - Adobe, Office → subscriptions.saas

            EDUCATION (education.*)
            - Escola, Colégio, Faculdade → education.school
            - Curso, Aula Online → education.courses
            - Livraria → education.books
            - Papelaria → education.supplies

            PERSONAL CARE (personalCare.*)
            - Salão, Cabeleireiro, Barbearia → personalCare.hairBeauty
            - Cosméticos, Perfumaria → personalCare.cosmetics

            FINANCIAL (financial.*)
            - Tarifa, Juros, Encargo → financial.bankFees
            - Imposto, Taxa → financial.taxes

            PETS (pets.*)
            - Petshop → pets.store
            - Veterinário → pets.vet

            HOUSING (housing.*)
            - Aluguel → housing.rent
            - Energia, Luz → housing.energy
            - Água → housing.water
            - Internet → housing.internet
            - Telefone → housing.phone
            """

        case .es:
            return """
            LANGUAGE CONTEXT:
            The user's app language is Spanish (es).
            Bank statements are likely in Spanish. Interpret merchant names using Spanish business vocabulary.

            IMPORTANT:
            - Ignore noise like payment types (PAGO, COMPRA, TRANSFERENCIA)
            - Focus on business type and merchant identity

            KEY CATEGORY MAPPINGS (Spanish):

            HEALTH (health.*)
            - Farmacia, Droguería → health.pharmacy
            - Clínica, Hospital, Centro Médico → health.consultation
            - Dentista → health.dentist

            TRANSPORT (transport.*)
            - Gasolinera, Estación de Servicio → transport.fuel
            - Uber, Cabify, Bolt → transport.rideHailing
            - Parking, Aparcamiento → transport.parking
            - Peaje → transport.tolls
            - Metro, Renfe, Bus → transport.publicTransit

            GROCERIES (groceries.*)
            - Supermercado, Mercado → groceries.market
            - Frutería, Verdulería → groceries.produce
            - Carnicería → groceries.butcher
            - Panadería → groceries.bakery

            RESTAURANTS (restaurants.*)
            - Restaurante → restaurants.lunchDinner
            - Glovo, Uber Eats → restaurants.delivery
            - McDonald's → restaurants.fastFood
            - Café → restaurants.coffeeSnack
            - Bar → restaurants.bars

            SHOPPING (shopping.*)
            - Tienda, Comercio → shopping.gifts
            - Ropa → shopping.clothes
            - Zapatos → shopping.shoes

            SUBSCRIPTIONS (subscriptions.*)
            - Netflix, Spotify → subscriptions.streaming / subscriptions.music
            - iCloud, Google One → subscriptions.cloudBackup

            EDUCATION (education.*)
            - Escuela, Colegio → education.school
            - Curso → education.courses
            - Librería → education.books
            - Papelería → education.supplies

            PERSONAL CARE (personalCare.*)
            - Peluquería, Barbería → personalCare.hairBeauty
            - Cosméticos → personalCare.cosmetics

            FINANCIAL (financial.*)
            - Comisión bancaria → financial.bankFees
            - Impuesto → financial.taxes

            PETS (pets.*)
            - Tienda de mascotas → pets.store
            - Veterinario → pets.vet

            HOUSING (housing.*)
            - Alquiler → housing.rent
            - Luz → housing.energy
            - Agua → housing.water
            - Internet → housing.internet
            """

        case .en:
            return """
            LANGUAGE CONTEXT:
            The user's app language is English (en).
            Bank statements are likely in English. Interpret merchant names using global business vocabulary.

            IMPORTANT:
            - Merchant strings may include noise (PAYMENT, PURCHASE, TRANSFER, etc.)
            - Focus on identifying the business type and brand

            KEY CATEGORY MAPPINGS (English):

            HEALTH (health.*)
            - Pharmacy, Drugstore → health.pharmacy
            - Clinic, Hospital → health.consultation
            - Dentist → health.dentist

            TRANSPORT (transport.*)
            - Gas station, Fuel → transport.fuel
            - Uber, Lyft → transport.rideHailing
            - Parking → transport.parking
            - Toll → transport.tolls
            - Subway, Bus, Train → transport.publicTransit

            GROCERIES (groceries.*)
            - Supermarket, Grocery → groceries.market
            - Produce store → groceries.produce
            - Butcher → groceries.butcher
            - Bakery → groceries.bakery

            RESTAURANTS (restaurants.*)
            - Restaurant → restaurants.lunchDinner
            - Uber Eats, DoorDash → restaurants.delivery
            - Fast food → restaurants.fastFood
            - Coffee shop → restaurants.coffeeSnack
            - Bar → restaurants.bars

            SHOPPING (shopping.*)
            - Retail store → shopping.gifts
            - Clothing store → shopping.clothes
            - Shoe store → shopping.shoes

            SUBSCRIPTIONS (subscriptions.*)
            - Netflix, Spotify → subscriptions.streaming / subscriptions.music
            - iCloud, Google One → subscriptions.cloudBackup

            EDUCATION (education.*)
            - School → education.school
            - Courses → education.courses
            - Bookstore → education.books
            - Supplies → education.supplies

            PERSONAL CARE (personalCare.*)
            - Hair salon, Barber → personalCare.hairBeauty
            - Cosmetics → personalCare.cosmetics

            FINANCIAL (financial.*)
            - Bank fee → financial.bankFees
            - Taxes → financial.taxes

            PETS (pets.*)
            - Pet store → pets.store
            - Vet → pets.vet

            HOUSING (housing.*)
            - Rent → housing.rent
            - Electricity → housing.energy
            - Water → housing.water
            - Internet → housing.internet
            """
        }
    }
}
