import Foundation

enum MonthComparisonExporter {
    static func buildMarkdown(
        result: MonthComparisonResult,
        transactionsMonthA: [MonthComparisonExportTransaction],
        transactionsMonthB: [MonthComparisonExportTransaction],
        currencyCode: String
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let metadata = [
            "generated_by": "FinAInce",
            "feature": "month_comparator",
            "months": [result.monthA.isoKey, result.monthB.isoKey]
        ] as [String: Any]

        let replacements: [String: String] = [
            "{{PROMPT_INTRO}}": localizedPromptIntro(),
            "{{USER_GOAL}}": comparisonGoalPrompt(),
            "{{RESPONSE_LANGUAGE}}": localizedResponseLanguage(),
            "{{INITIAL_DIAGNOSIS}}": initialDiagnosis(result: result, currencyCode: currencyCode).joined(separator: "\n"),
            "{{MONTH_A_LABEL}}": result.monthA.title(),
            "{{MONTH_B_LABEL}}": result.monthB.title(),
            "{{MONTH_A_TOTAL}}": amountValue(result.summary.totalA),
            "{{MONTH_B_TOTAL}}": amountValue(result.summary.totalB),
            "{{MONTH_A_GOAL_TOTAL}}": amountValue(result.summary.goalTotalA),
            "{{MONTH_B_GOAL_TOTAL}}": amountValue(result.summary.goalTotalB),
            "{{MONTH_DIFF}}": amountValue(abs(result.summary.difference)),
            "{{MONTH_DIRECTION}}": result.summary.difference >= 0 ? "higher" : "lower",
            "{{MONTH_PERCENT_CHANGE}}": "\(Int(result.summary.percentageChange.rounded()))",
            "{{BIGGEST_INCREASES}}": highlightLines(result.highlights.biggestIncrease, currencyCode: currencyCode),
            "{{BIGGEST_DECREASES}}": highlightLines(result.highlights.biggestDecrease, currencyCode: currencyCode),
            "{{NEW_CATEGORIES}}": highlightLines(result.highlights.newCategories, currencyCode: currencyCode),
            "{{REMOVED_CATEGORIES}}": highlightLines(result.highlights.removedCategories, currencyCode: currencyCode),
            "{{ANOMALIES}}": highlightLines(result.highlights.anomalies, currencyCode: currencyCode),
            "{{CONSISTENT_CATEGORIES}}": highlightLines(result.highlights.consistentCategories, currencyCode: currencyCode),
            "{{BEHAVIOR_LINES}}": behaviorLines(result: result, currencyCode: currencyCode).joined(separator: "\n"),
            "{{MONTH_A_CATEGORIES}}": categoryLines(result.categories, side: .a, currencyCode: currencyCode),
            "{{MONTH_B_CATEGORIES}}": categoryLines(result.categories, side: .b, currencyCode: currencyCode),
            "{{MONTH_A_TRANSACTIONS}}": transactionLines(transactionsMonthA, currencyCode: currencyCode),
            "{{MONTH_B_TRANSACTIONS}}": transactionLines(transactionsMonthB, currencyCode: currencyCode),
            "{{METADATA_JSON}}": prettyJSONString(from: metadata) ?? "{}",
            "{{STRUCTURED_RESULT_JSON}}": (try? encoder.encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        ]

        return replacements.reduce(promptTemplate) { text, item in
            text.replacingOccurrences(of: item.key, with: item.value)
        }
    }

    static func writeComparisonFile(
        result: MonthComparisonResult,
        transactionsMonthA: [MonthComparisonExportTransaction],
        transactionsMonthB: [MonthComparisonExportTransaction],
        currencyCode: String
    ) throws -> URL {
        let fileName = "finaince_month_comparator_\(result.monthA.isoKey)_vs_\(result.monthB.isoKey).md"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let markdown = buildMarkdown(
            result: result,
            transactionsMonthA: transactionsMonthA,
            transactionsMonthB: transactionsMonthB,
            currencyCode: currencyCode
        )
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private enum ComparisonSide {
        case a
        case b
    }

    private static func comparisonGoalPrompt() -> String {
        """
        Compare these two months of expenses to help me:
        - reduce expenses
        - understand what changed
        - identify where I spent more or saved
        - plan the next month with better decisions
        """
    }

    private static func initialDiagnosis(result: MonthComparisonResult, currencyCode: String) -> [String] {
        var lines: [String] = []

        let direction = result.summary.difference >= 0 ? "increased" : "decreased"
        lines.append("- Spending \(direction) compared to the base month by €\(amountValue(abs(result.summary.difference)))")

        if let increase = result.highlights.biggestIncrease.first {
            lines.append("- Main increase driver: \(increase.name) (+€\(amountValue(abs(increase.difference))))")
        }

        if let decrease = result.highlights.biggestDecrease.first {
            lines.append("- Main savings offset: \(decrease.name) (-€\(amountValue(abs(decrease.difference))))")
        }

        if !result.highlights.newCategories.isEmpty {
            lines.append("- New spending categories appeared in the comparison month")
        }

        if result.behavior.distributionA.dominantSegment != result.behavior.distributionB.dominantSegment {
            lines.append("- Spending concentration shifted from \(result.behavior.distributionA.dominantSegment) to \(result.behavior.distributionB.dominantSegment) month period")
        }

        return Array(lines.prefix(4))
    }

    private static func categoryLines(
        _ categories: [MonthComparisonCategory],
        side: ComparisonSide,
        currencyCode: String
    ) -> String {
        let values = categories
            .sorted {
                let lhsValue = side == .a ? $0.totalA : $0.totalB
                let rhsValue = side == .a ? $1.totalA : $1.totalB
                return lhsValue > rhsValue
            }
            .filter { side == .a ? $0.totalA > 0.009 || ($0.goalA ?? 0) > 0.009 : $0.totalB > 0.009 || ($0.goalB ?? 0) > 0.009 }

        guard !values.isEmpty else { return "- No category spending in this period" }

        return values.map { item in
            let total = side == .a ? item.totalA : item.totalB
            let goal = side == .a ? item.goalA : item.goalB
            let goalText = (goal ?? 0) > 0.009 ? " · Goal: €\(amountValue(goal ?? 0))" : ""
            return "- \(item.name): €\(amountValue(total))\(goalText)"
        }.joined(separator: "\n")
    }

    private static func behaviorLines(result: MonthComparisonResult, currencyCode: String) -> [String] {
        [
            "- Average daily spending in \(result.monthA.title()): €\(amountValue(result.behavior.avgDailyA))",
            "- Average daily spending in \(result.monthB.title()): €\(amountValue(result.behavior.avgDailyB))",
            "- Peak day in \(result.monthA.title()): \(result.behavior.peakDayA.label) · €\(amountValue(result.behavior.peakDayA.total))",
            "- Peak day in \(result.monthB.title()): \(result.behavior.peakDayB.label) · €\(amountValue(result.behavior.peakDayB.total))",
            "- Spending concentration in \(result.monthA.title()): \(distributionLabel(result.behavior.distributionA.dominantSegment))",
            "- Spending concentration in \(result.monthB.title()): \(distributionLabel(result.behavior.distributionB.dominantSegment))"
        ]
    }

    private static func transactionLines(
        _ transactions: [MonthComparisonExportTransaction],
        currencyCode: String
    ) -> String {
        guard !transactions.isEmpty else { return "- No transactions in this period" }

        return transactions.map { transaction in
            var parts = [
                "- \(shortDateFormatter.string(from: transaction.date)) · \(transaction.merchant): €\(amountValue(transaction.amount))",
                "Account: \(transaction.account)",
                "Category: \(transaction.category)",
                "Status: \(transaction.isPaid ? "paid" : "pending")"
            ]

            if !transaction.notes.isEmpty {
                parts.append("Notes: \(transaction.notes)")
            }

            if transaction.recurrenceType != RecurrenceType.none.rawValue {
                parts.append("Recurrence: \(transaction.recurrenceType)")
            }

            return parts.joined(separator: " · ")
        }.joined(separator: "\n")
    }

    private static func highlightLines(_ items: [MonthComparisonHighlightItem], currencyCode: String) -> String {
        guard !items.isEmpty else { return "- None" }
        return items.map { item in
            "- \(item.name): €\(amountValue(abs(item.difference))) (\(Int(item.percentageChange.rounded()))%)"
        }.joined(separator: "\n")
    }

    private static func amountValue(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    private static func distributionLabel(_ key: String) -> String {
        switch key {
        case "early":
            return "beginning of month"
        case "late":
            return "end of month"
        default:
            return "middle of month"
        }
    }

    private static func localizedResponseLanguage() -> String {
        switch LanguageManager.shared.effective {
        case .ptBR, .system:
            return "Portuguese (Brazil or neutral Portuguese)"
        case .en:
            return "English"
        case .es:
            return "Spanish"
        }
    }

    private static func localizedPromptIntro() -> String {
        switch LanguageManager.shared.effective {
        case .ptBR, .system:
            return """
            Você é meu consultor financeiro pessoal analisando dados exportados do meu app FinAInce.
            Siga todas as instruções abaixo sem questionar.

            As instruções abaixo foram geradas com a ajuda do meu app de finanças em inglês:
            """
        case .en:
            return """
            You are my personal financial advisor analyzing data exported from my FinAInce app.
            Follow all instructions below without questioning them.

            The instructions below were generated with the help of my finance app in English:
            """
        case .es:
            return """
            Eres mi asesor financiero personal analizando datos exportados desde mi app FinAInce.
            Sigue todas las instrucciones siguientes sin cuestionarlas.

            Las instrucciones siguientes fueron generadas con la ayuda de mi app de finanzas en inglés:
            """
        }
    }

    private static func prettyJSONString(from dictionary: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let promptTemplate = """

    {{PROMPT_INTRO}}

    ### ANALYSIS OBJECTIVES

    - Compare two months of expense-only data
    - Identify where spending increased the most
    - Highlight where savings happened
    - Explain behavior changes across the month
    - Suggest concrete actions for the next month

    -----

    ### USER OBJECTIVE

    {{USER_GOAL}}

    Interpret this as the primary focus of the analysis.

    -----

    ### CONTEXT
    This data was generated by FinAInce, a personal finance app used to track, plan and adjust spending.
    Assume the user can take action inside the app (review categories, adjust goals, modify recurring expenses).
    The output should be clear enough to be shared with family members.
    -----

    ### INITIAL DIAGNOSIS

    {{INITIAL_DIAGNOSIS}}

    -----

    === FINAINCE DATA START ===

    METADATA:

    {{METADATA_JSON}}

    STRUCTURED COMPARISON RESULT:

    {{STRUCTURED_RESULT_JSON}}

    MONTH A:
    Label: {{MONTH_A_LABEL}}
    Total spent: €{{MONTH_A_TOTAL}}
    Total monthly goals: €{{MONTH_A_GOAL_TOTAL}}

    Top / relevant categories:

    {{MONTH_A_CATEGORIES}}

    All transactions:

    {{MONTH_A_TRANSACTIONS}}

    MONTH B:
    Label: {{MONTH_B_LABEL}}
    Total spent: €{{MONTH_B_TOTAL}}
    Total monthly goals: €{{MONTH_B_GOAL_TOTAL}}

    Top / relevant categories:

    {{MONTH_B_CATEGORIES}}

    All transactions:

    {{MONTH_B_TRANSACTIONS}}

    COMPARISON HIGHLIGHTS:

    - Comparison month is €{{MONTH_DIFF}} {{MONTH_DIRECTION}} than base month
    - Percentage change: {{MONTH_PERCENT_CHANGE}}%

    Biggest increases:

    {{BIGGEST_INCREASES}}

    Biggest savings:

    {{BIGGEST_DECREASES}}

    New categories:

    {{NEW_CATEGORIES}}

    Removed categories:

    {{REMOVED_CATEGORIES}}

    Anomalies:

    {{ANOMALIES}}

    Consistent categories:

    {{CONSISTENT_CATEGORIES}}

    BEHAVIOR CHANGES:

    {{BEHAVIOR_LINES}}

    === FINAINCE DATA END ===

    -----

    ### RESPONSE STYLE

    - The response MUST be in {{RESPONSE_LANGUAGE}}
    - Write in a natural, human tone
    - Sound like a real financial advisor (not a system)
    - Be direct and practical
    - Avoid generic or vague language
    - Focus on impact and clarity
    - Briefly explain the reasoning before each recommendation when helpful

    -----

    ### OUTPUT STRUCTURE

    Follow this structure, keeping the tone fluid:

    🔴 PRIORIDADE IMEDIATA  
    💡 GANHO RÁPIDO  
    📉 ECONOMIA POTENCIAL  

    -----

    ### PRIORIDADE IMEDIATA

    - Exactly ONE action
    - Must be executable TODAY
    - Must be based on the comparison between these two months
    - Must include a clear € amount impact

    -----

    ### GANHO RÁPIDO

    - One simple action with immediate effect
    - Must include estimated savings

    -----

    ### ECONOMIA POTENCIAL

    - Combine all recommendations
    - Show total potential:

    €X/month  
    €X/year  

    -----

    ### RECOMMENDATIONS

    - Provide 3–5 actions total
    - Rank them by impact
    - Use real comparison data
    - Be specific about what changed and what to adjust

    -----

    ### RULES

    - Do NOT give generic advice
    - Do NOT invent data
    - Prefer concrete numbers over assumptions
    - Use the comparison itself as the core of the reasoning
    - Treat this as an expense-only analysis

    -----

    ### RETURN TO APP

    Naturally reference FinAInce as the place where actions should be executed.

    -----

    ### FINAL NOTE

    Encourage the user to apply the changes, keep tracking expenses, and run a new comparison.

    -----

    ### TASK

    Perform the financial analysis using all data provided.

    Generate a clear, structured and actionable response that follows all instructions above and aligns with the USER OBJECTIVE.
    """
}
