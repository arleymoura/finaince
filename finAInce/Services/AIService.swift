import Foundation

// MARK: - Transaction draft (rascunho criado pela tool CriarTransacao)

struct TransactionDraft: Sendable {
    let amount:       Double
    let typeRaw:      String   // "expense"
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
        currencyCode: String = "BRL",
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

        let thisMonth = transactions.filter {
            cal.component(.year,  from: $0.date) == year &&
            cal.component(.month, from: $0.date) == month &&
            $0.type == .expense
        }

        let total = thisMonth.reduce(0) { $0 + $1.amount }

        // Agrupa por categoria
        var byCategory: [String: Double] = [:]
        for tx in thisMonth {
            let cat = tx.category?.name ?? "Uncategorized"
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
            let cat   = tx.category?.name ?? "uncategorized"
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

        ## Critical output rules
        - Never reveal chain-of-thought, internal reasoning, or analysis steps.
        - Never mention functions, tools, queries, or that you are looking up data.
        - Never start with phrases like "I'll check", "Let me verify", "Analyzing", or similar.
        - Present the results directly, as if you naturally know the user's financial data.
        - If the request is ambiguous or lacks important context such as period, category, or account,
          ask one direct clarification question before answering.

        ## User financial data
        Today: \(now.formatted(.dateTime.day().month(.wide).year()))

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
        let amount: Double
        let storeName: String
        let suggestedCategoryName: String
        let notes: String
        let date: Date?
    }

    struct CategorySuggestionOption: Sendable {
        let categoryName: String
        let subcategoryName: String?
    }

    struct CategorySuggestionResult: Sendable {
        let categoryName: String
        let subcategoryName: String?
        /// Nome limpo do estabelecimento extraído pela IA da descrição bruta do extrato.
        /// Pode ser nil se a IA não conseguir identificar ou se a entrada já for um nome limpo.
        let resolvedMerchantName: String?
    }

    /// Sugere uma categoria para um estabelecimento quando não há histórico local suficiente.
    static func suggestCategory(
        merchantName: String,
        settings: AISettings,
        options: [CategorySuggestionOption]
    ) async throws -> CategorySuggestionResult? {
        let merchant = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchant.isEmpty, !options.isEmpty else { return nil }

        let optionsText = options.map { option in
            if let subcategoryName = option.subcategoryName, !subcategoryName.isEmpty {
                return "- \(option.categoryName) / \(subcategoryName)"
            }
            return "- \(option.categoryName)"
        }.joined(separator: "\n")

        let system = """
        You are a merchant categoriser. Given a bank statement description and a list of \
        expense categories, return a JSON object with four fields:
        - "merchant": the clean brand name (e.g. "Cinemark", "Netflix", "Uber"). \
          Use the well-known brand name, NOT the business type. \
          If the brand is unrecognisable, clean up the raw text.
        - "category": the best matching category, copied verbatim from the list. \
          If unsure, use empty string.
        - "subcategory": the best matching subcategory, copied verbatim from the list. \
          If none fits, use empty string.
        - "confidence": integer 0–100 representing how confident you are in the category match. \
          70 or above means you are reasonably sure. Below 70 means you are guessing.

        Rules: only use category/subcategory values present in the list. No markdown. No extra text. JSON only.
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
            let data = clean.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            #if DEBUG
            print("🤖 [AI Category] ❌ JSON parse failed for: \(clean)")
            #endif
            throw AIError.invalidResponse
        }

        let categoryName    = (json["category"]    as? String) ?? ""
        let subcategoryName = (json["subcategory"] as? String) ?? ""
        let merchantName    = (json["merchant"]    as? String) ?? ""
        let confidence      = (json["confidence"]  as? Int)    ?? 100  // default high if omitted

        #if DEBUG
        print("🤖 [AI Category] confidence: \(confidence)%")
        #endif

        guard !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // Below 70 % confidence → fall back to "Outros" if it exists in the list, else nil
        if confidence < 70 {
            #if DEBUG
            print("🤖 [AI Category] ⚠️ confidence \(confidence)% < 70 — falling back to Outros")
            #endif
            let outros = options.first {
                $0.categoryName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .contains("outro")
            }
            guard let outros else { return nil }
            return CategorySuggestionResult(
                categoryName:         outros.categoryName,
                subcategoryName:      nil,
                resolvedMerchantName: merchantName.isEmpty ? nil : merchantName
            )
        }

        return CategorySuggestionResult(
            categoryName:         categoryName,
            subcategoryName:      subcategoryName.isEmpty  ? nil : subcategoryName,
            resolvedMerchantName: merchantName.isEmpty     ? nil : merchantName
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

        //todo:localizar aqui
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

        // Deduplicate root category names preserving order
        var seen = Set<String>()
        let rootNames: [String] = options.compactMap { o in
            seen.insert(o.categoryName).inserted ? o.categoryName : nil
        }

        // ── Step 1: root category + confidence ──────────────────────────────
        let step1 = """
        Merchant: "\(merchant)"
        Categories: \(rootNames.joined(separator: ", "))

        Which single category from the list above best matches this merchant?
        Reply in this exact format: CATEGORY_NAME|CONFIDENCE
        where CONFIDENCE is a number from 0 to 100 (your certainty).
        Example: "Lazer|85"
        If none fits, reply with nothing.
        """

        #if DEBUG
        print("🤖 [AI/local step1] prompt: \(step1)")
        #endif

        guard let rawStep1 = await LocalAIService.classify(prompt: step1), !rawStep1.isEmpty else {
            return nil
        }

        #if DEBUG
        print("🤖 [AI/local step1] response: '\(rawStep1)'")
        #endif

        // Parse "CategoryName|confidence" — confidence is optional for robustness
        let step1Parts  = rawStep1.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let rawRoot     = step1Parts[0]
        let localConf   = step1Parts.count > 1 ? Int(step1Parts[1]) ?? 100 : 100

        let fold: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        let foldedRoot = fold(rawRoot)
        guard !foldedRoot.isEmpty else { return nil }

        let matchedRoot = rootNames.first { fold($0) == foldedRoot }
            ?? rootNames.first { fold($0).contains(foldedRoot) || foldedRoot.contains(fold($0)) }

        guard let matchedRoot else {
            #if DEBUG
            print("🤖 [AI/local step1] ❌ '\(rawRoot)' not found in [\(rootNames.joined(separator: ", "))]")
            #endif
            return nil
        }

        #if DEBUG
        print("🤖 [AI/local step1] ✅ matched root: '\(matchedRoot)' confidence: \(localConf)%")
        #endif

        // Below 70 % → fall back to "Outros" if available, else nil
        if localConf < 70 {
            #if DEBUG
            print("🤖 [AI/local step1] ⚠️ confidence \(localConf)% < 70 — falling back to Outros")
            #endif
            let outros = rootNames.first {
                fold($0).contains("outro")
            }
            return CategorySuggestionResult(
                categoryName:         outros ?? matchedRoot,
                subcategoryName:      nil,
                resolvedMerchantName: nil
            )
        }
        // ── Step 2: subcategory (only if children exist) ─────────────────────
        let subNames = options.compactMap { o -> String? in
            guard o.categoryName == matchedRoot, let sub = o.subcategoryName else { return nil }
            return sub
        }

        var matchedSub: String? = nil

        if !subNames.isEmpty {
            let step2 = """
            Merchant: "\(merchant)" (category: \(matchedRoot))
            Subcategories: \(subNames.joined(separator: ", "))

            Which subcategory best matches? Reply with only the subcategory name. If none fits, reply with nothing.
            """

            #if DEBUG
            print("🤖 [AI/local step2] prompt: \(step2)")
            #endif

            if let rawSub = await LocalAIService.classify(prompt: step2), !rawSub.isEmpty {
                #if DEBUG
                print("🤖 [AI/local step2] response: '\(rawSub)'")
                #endif
                let foldedSub = fold(rawSub)
                matchedSub = subNames.first { fold($0) == foldedSub }
                    ?? subNames.first { fold($0).contains(foldedSub) || foldedSub.contains(fold($0)) }
                #if DEBUG
                print("🤖 [AI/local step2] matched sub: '\(matchedSub ?? "none")'")
                #endif
            }
        }

        return CategorySuggestionResult(
            categoryName:         matchedRoot,
            subcategoryName:      matchedSub,
            resolvedMerchantName: nil
        )
    }

    /// Analisa texto extraído via OCR de um recibo e retorna valor, estabelecimento, categoria sugerida e observação.
    static func analyzeReceipt(
        ocrText: String,
        settings: AISettings,
        categoryNames: [String] = []
    ) async throws -> ReceiptResult {

        let categoriesHint = categoryNames.isEmpty
            ? ""
            : "\nCategorias disponíveis: \(categoryNames.joined(separator: ", ")). Escolha a mais adequada ou retorne string vazia."

        let system = """
        You are a receipt data extractor. Analyze the text and return ONLY valid JSON, with no markdown.
        Exact format: {"valor": 0.0, "estabelecimento": "", "categoria": "", "data": "yyyy-MM-dd", "observacao": ""}
        """
        let user = """
        Extract the data from this receipt:\(categoriesHint)

        \(ocrText)

        Return JSON only:
        {
          "valor": <total paid, decimal number>,
          "estabelecimento": "<merchant name>",
          "categoria": "<best matching category from the list, or empty string>",
          "data": "<purchase date in yyyy-MM-dd, or empty string>",
          "observacao": "<useful detail in one short sentence, or empty string>"
        }
        """

        let responseText: String

        // ── Apple Intelligence (on-device, sem chave de API) ──────────────
        if settings.provider == .local {
            let emptyContext = FinanceContext(
                transactions: [],
                goals: [],
                accounts: [],
                currencyCode: "BRL",
                appLanguageCode: LanguageManager.shared.effective.rawValue,
                localeIdentifier: Locale.current.identifier,
                timeZoneIdentifier: TimeZone.current.identifier
            )
            // Combine system instructions + user query into a single message
            // so that LocalAIService's own system prompt doesn't interfere
            let combinedMessage = "\(system)\n\n\(user)"
            let result = try await LocalAIService.send(
                userMessage: combinedMessage,
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

        guard
            let data = clean.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AIError.invalidResponse }

        let amount: Double = {
            if let d = json["valor"] as? Double { return d }
            if let s = json["valor"] as? String { return Double(s) ?? 0 }
            return 0
        }()
        let storeName  = (json["estabelecimento"] as? String) ?? ""
        let category   = (json["categoria"]      as? String) ?? ""
        let notes      = (json["observacao"]     as? String) ?? ""
        let dateString = (json["data"]           as? String) ?? ""
        let date       = CSVImportService.parseDate(dateString)
        return ReceiptResult(amount: amount, storeName: storeName,
                             suggestedCategoryName: category, notes: notes, date: date)
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
}
