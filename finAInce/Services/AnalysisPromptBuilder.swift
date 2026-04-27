import Foundation

struct AnalysisPromptBuilder {
    static func buildDeepAnalysisPrompt(
        transactions: [Transaction],
        accounts: [Account],
        goals: [Goal],
        month: Int,
        year: Int,
        currencyCode: String,
        focus: String,
        analysisGoal: String = "Investigate this insight in depth and produce practical recommendations."
    ) -> String {
        let scopedTransactions = transactions.filter { transaction in
            let components = Calendar.current.dateComponents([.month, .year], from: transaction.date)
            return components.month == month && components.year == year
        }

        let scopedInsights = InsightEngine.compute(
            transactions: transactions,
            accounts: accounts,
            goals: goals,
            month: month,
            year: year,
            currencyCode: currencyCode
        )

        let insightLines = scopedInsights.prefix(5).map { insight in
            var line = "- \(insight.title): \(insight.body)"
            if let amount = insight.metadata?.amount {
                line += " | valor: \(amount.asCurrency(currencyCode))"
            }
            if let percentage = insight.metadata?.percentage {
                line += " | variacao: \(Int(percentage.rounded()))%"
            }
            return line
        }

        let insightsBlock = insightLines.isEmpty
            ? "- Nenhum insight adicional calculado para este periodo."
            : insightLines.joined(separator: "\n")

        let exportBlock = FinancialAnalysisExporter.buildAnalysisText(
            transactions: transactions,
            accounts: accounts,
            goals: goals,
            selectedMonth: month,
            selectedYear: year,
            adults: 0,
            children: 0,
            currencyCode: currencyCode,
            analysisGoal: analysisGoal
        )

        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.effective.locale
        formatter.dateFormat = "MMMM yyyy"
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = 1
        let periodDate = Calendar.current.date(from: dateComponents) ?? Date()
        let periodLabel = formatter.string(from: periodDate).capitalized

        let focusTransactions = scopedTransactions
            .filter { transaction in
                let description = [
                    transaction.placeName,
                    transaction.notes,
                    transaction.category?.displayName,
                    transaction.subcategory?.displayName
                ]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")

                return description.contains(focus.lowercased())
            }
            .sorted { $0.date > $1.date }
            .prefix(15)
            .map { transaction in
                let place = transaction.placeName ?? transaction.category?.displayName ?? "No description"
                return "- \(transaction.date.formatted(.dateTime.day().month(.abbreviated))) | \(place) | \(transaction.amount.asCurrency(currencyCode))"
            }
            .joined(separator: "\n")

        let focusTransactionsBlock = focusTransactions.isEmpty
            ? "- No transactions were found through direct textual matching with the focus."
            : focusTransactions

        let responseLanguage = responseLanguageInstruction(for: LanguageManager.shared.effective)

        return """
        I need a deep financial analysis based on the data below.

        Reply in \(responseLanguage).
        Be objective, practical, and structured.
        Do not repeat the context in full; interpret it.

        PRIMARY OBJECTIVE
        - Investigate this point in depth: \(focus)
        - Main period: \(periodLabel)
        - Expected task:
          1. explain what most likely happened
          2. identify root causes
          3. say whether this looks like a one-off event or a trend
          4. list short-term risks
          5. suggest concrete, prioritized actions

        INSIGHTS ALREADY IDENTIFIED BY THE APP
        \(insightsBlock)

        TRANSACTIONS MOST RELATED TO THE FOCUS
        \(focusTransactionsBlock)

        FULL CONTEXT EXPORTED BY THE APP
        \(exportBlock)
        """
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
