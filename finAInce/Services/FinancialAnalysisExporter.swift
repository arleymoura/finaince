import Foundation
import SwiftData

struct FinancialAnalysisExporter {
    static func buildAnalysisText(
        transactions: [Transaction],
        accounts: [Account],
        goals: [Goal],
        selectedMonth: Int,
        selectedYear: Int,
        adults: Int,
        children: Int,
        currencyCode: String,
        analysisGoal: String,
        calendar: Calendar = .current
    ) -> String {
        let currentStart = startOfMonth(month: selectedMonth, year: selectedYear, calendar: calendar)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
        let nextStart = calendar.date(byAdding: .month, value: 1, to: currentStart) ?? currentStart

        let current = monthSnapshot(
            title: "CURRENT MONTH",
            start: currentStart,
            transactions: transactions,
            currencyCode: currencyCode,
            calendar: calendar
        )
        let previous = monthSnapshot(
            title: "PREVIOUS MONTH",
            start: previousStart,
            transactions: transactions,
            currencyCode: currencyCode,
            calendar: calendar
        )
        let next = nextMonthSnapshot(
            start: nextStart,
            transactions: transactions,
            currencyCode: currencyCode,
            calendar: calendar
        )

        let goalLines = goalsSection(
            goals: goals,
            transactions: transactions,
            monthStart: currentStart,
            currencyCode: currencyCode,
            calendar: calendar
        )
        let monthDifference = current.totalSpent - previous.totalSpent
        let initialDiagnosisText = initialDiagnosis(
            current: current,
            previous: previous,
            next: next,
            currencyCode: currencyCode
        ).joined(separator: "\n")
        let goalsBlock = goalLines.isEmpty ? "- No goals configured" : goalLines.joined(separator: "\n")
        let currentTopCategories = current.topCategories.isEmpty ? "- No spending in this period" : current.topCategories.joined(separator: "\n")
        let currentAllTransactions = current.allTransactions.isEmpty ? "- No transactions in this period" : current.allTransactions.joined(separator: "\n")
        let previousMonthDiffsText = previousMonthDiffs(current: current, previous: previous, currencyCode: currencyCode).joined(separator: "\n")
        let previousTopCategories = previous.topCategories.isEmpty ? "- No spending in this period" : previous.topCategories.joined(separator: "\n")
        let nextCommitments = next.pendingCommitments.isEmpty ? "- No pending commitments found" : next.pendingCommitments.joined(separator: "\n")

        let replacements: [String: String] = [
            "{{PROMPT_INTRO}}": localizedPromptIntro(),
            "{{USER_GOAL}}": analysisGoalPrompt(for: analysisGoal),
            "{{RESPONSE_LANGUAGE}}": localizedResponseLanguage(),
            "{{INITIAL_DIAGNOSIS}}": initialDiagnosisText,
            "{{USER_PROFILE}}": userProfile(adults: adults, children: children),
            "{{ACCOUNTS_BLOCK}}": accountsBlock(accounts),
            "{{GOALS_BLOCK}}": goalsBlock,
            "{{CURRENT_MONTH_TOTAL}}": amountValue(current.totalSpent),
            "{{CURRENT_MONTH_TOP_CATEGORIES}}": currentTopCategories,
            "{{CURRENT_MONTH_ALL_TRANSACTIONS}}": currentAllTransactions,
            "{{PREVIOUS_MONTH_TOTAL}}": amountValue(previous.totalSpent),
            "{{MONTH_DIFFERENCE}}": amountValue(abs(monthDifference)),
            "{{MONTH_DIRECTION}}": monthDifference >= 0 ? "higher" : "lower",
            "{{PREVIOUS_MONTH_DIFFS}}": previousMonthDiffsText,
            "{{PREVIOUS_MONTH_TOP_CATEGORIES}}": previousTopCategories,
            "{{NEXT_MONTH_TOTAL}}": amountValue(next.plannedExpenses),
            "{{NEXT_MONTH_COMMITMENTS}}": nextCommitments
        ]

        return replacements.reduce(Self.promptTemplate) { text, replacement in
            text.replacingOccurrences(of: replacement.key, with: replacement.value)
        }
    }

    static func writeAnalysisFile(text: String, selectedMonth: Int, selectedYear: Int, calendar: Calendar = .current) throws -> URL {
        let monthStart = startOfMonth(month: selectedMonth, year: selectedYear, calendar: calendar)
        let fileName = "finaince_analysis_\(fileMonthFormatter.string(from: monthStart))_\(selectedYear).md"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private struct MonthSnapshot {
        let totalSpent: Double
        let categoryTotals: [String: Double]
        let topCategories: [String]
        let allTransactions: [String]
    }

    private struct NextMonthSnapshot {
        let plannedExpenses: Double
        let pendingCommitments: [String]
    }

    private static func startOfMonth(month: Int, year: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return calendar.date(from: components) ?? calendar.startOfDay(for: Date())
    }

    private static func endOfMonth(start: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: 1, to: start) ?? start
    }

    private static func monthTransactions(inMonthStarting start: Date, from allTransactions: [Transaction], calendar: Calendar) -> [Transaction] {
        let end = endOfMonth(start: start, calendar: calendar)
        return allTransactions.filter { $0.date >= start && $0.date < end }
    }

    private static func monthSnapshot(
        title: String,
        start: Date,
        transactions: [Transaction],
        currencyCode: String,
        calendar: Calendar
    ) -> MonthSnapshot {
        let selectedMonthTransactions = monthTransactions(inMonthStarting: start, from: transactions, calendar: calendar)
        let expenseTransactions = selectedMonthTransactions.filter { $0.type == .expense }
        let totalSpent = expenseTransactions.reduce(0) { $0 + $1.amount }
        let categoryTotals = categoryTotals(for: expenseTransactions)

        let topCategories = categoryTotals
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { "- \($0.key): €\(amountValue($0.value))" }

        let allTransactions = selectedMonthTransactions
            .sorted { first, second in
                if first.date == second.date { return first.amount > second.amount }
                return first.date < second.date
            }
            .map { transactionAnalysisLine($0, currencyCode: currencyCode, includeRecurrence: true) }

        return MonthSnapshot(
            totalSpent: totalSpent,
            categoryTotals: categoryTotals,
            topCategories: Array(topCategories),
            allTransactions: Array(allTransactions)
        )
    }

    private static func nextMonthSnapshot(
        start: Date,
        transactions: [Transaction],
        currencyCode: String,
        calendar: Calendar
    ) -> NextMonthSnapshot {
        let selectedMonthTransactions = monthTransactions(inMonthStarting: start, from: transactions, calendar: calendar)
        let plannedTransactions = selectedMonthTransactions
            .filter { transaction in
                guard transaction.type == .expense else { return false }
                if !transaction.isPaid { return true }
                if transaction.recurrenceType == .monthly { return true }
                if transaction.recurrenceType == .installment { return true }
                return false
            }
            .sorted { first, second in
                if first.date == second.date { return first.amount > second.amount }
                return first.date < second.date
            }

        let plannedExpenses = plannedTransactions.reduce(0) { $0 + $1.amount }
        let pendingCommitments = plannedTransactions.prefix(10).map { transaction in
            transactionAnalysisLine(transaction, currencyCode: currencyCode, includeRecurrence: true)
        }

        return NextMonthSnapshot(
            plannedExpenses: plannedExpenses,
            pendingCommitments: Array(pendingCommitments)
        )
    }

    private static func goalsSection(
        goals: [Goal],
        transactions: [Transaction],
        monthStart: Date,
        currencyCode: String,
        calendar: Calendar
    ) -> [String] {
        let selectedMonthTransactions = monthTransactions(inMonthStarting: monthStart, from: transactions, calendar: calendar)
            .filter { $0.type == .expense }

        return goals
            .filter { $0.isActive }
            .sorted { $0.createdAt < $1.createdAt }
            .map { goal in
                let spent = spentAmount(for: goal, in: selectedMonthTransactions)
                let progress = goal.targetAmount > 0 ? min(999, (spent / goal.targetAmount) * 100) : 0
                let categoryName = validGoalName(goal.category?.displayName ?? goal.title)
                return "- Category: \(categoryName): €\(amountValue(goal.targetAmount)) target — \(Int(progress.rounded()))% completed · finaince://goal/\(categoryName)"
            }
    }

    private static func spentAmount(for goal: Goal, in transactions: [Transaction]) -> Double {
        guard goal.category != nil else {
            return transactions.reduce(0) { $0 + $1.amount }
        }

        return transactions
            .filter { transaction in
                goal.matches(transaction)
            }
            .reduce(0) { $0 + $1.amount }
    }

    private static func keyDifferences(
        current: MonthSnapshot,
        previous: MonthSnapshot,
        currencyCode: String
    ) -> [String] {
        guard current.totalSpent > 0 || previous.totalSpent > 0 else {
            return ["- No spending in either period"]
        }

        let diff = current.totalSpent - previous.totalSpent
        let direction = diff >= 0 ? "higher" : "lower"
        var lines = ["- Current month is \(abs(diff).asCurrency(currencyCode)) \(direction) than previous month"]

        let categories = Set(current.categoryTotals.keys).union(previous.categoryTotals.keys)
        let categoryDiffs = categories.map { category -> (String, Double) in
            let currentValue = current.categoryTotals[category] ?? 0
            let previousValue = previous.categoryTotals[category] ?? 0
            return (category, currentValue - previousValue)
        }
        .sorted { abs($0.1) > abs($1.1) }
        .prefix(3)

        for item in categoryDiffs where abs(item.1) >= 0.01 {
            let direction = item.1 >= 0 ? "up" : "down"
            lines.append("- \(item.0): \(direction) \(abs(item.1).asCurrency(currencyCode))")
        }

        return lines
    }

    private static func analysisGoalPrompt(for goal: String) -> String {
        let cleanedGoal = goal
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !cleanedGoal.isEmpty else {
            return "Provide practical recommendations based on the user's selected objective."
        }

        return cleanedGoal
    }

    private static func initialDiagnosis(
        current: MonthSnapshot,
        previous: MonthSnapshot,
        next: NextMonthSnapshot,
        currencyCode: String
    ) -> [String] {
        var lines: [String] = []
        let diff = current.totalSpent - previous.totalSpent
        let direction = diff >= 0 ? "increased" : "decreased"
        lines.append("- Spending \(direction) compared to last month (€\(amountValue(abs(diff))))")

        let drivers = categoryDrivers(current: current, previous: previous).prefix(2).map(\.category)
        if !drivers.isEmpty {
            lines.append("- \(drivers.joined(separator: " and ")) \(drivers.count == 1 ? "is" : "are") the main \(diff >= 0 ? "increase" : "change") driver")
        }

        let fixedTotal = current.categoryTotals
            .filter { isFixedCostCategory($0.key) }
            .reduce(0) { $0 + $1.value }
        if current.totalSpent > 0 {
            let fixedRatio = fixedTotal / current.totalSpent
            if fixedRatio >= 0.45 {
                lines.append("- Fixed costs are high relative to total spending (\(Int((fixedRatio * 100).rounded()))%)")
            }
        }

        if next.plannedExpenses > 0 {
            let threshold = max(current.totalSpent * 0.5, 1)
            if next.plannedExpenses >= threshold {
                lines.append("- Next month already has significant committed expenses (€\(amountValue(next.plannedExpenses)))")
            }
        }

        if lines.count < 3 {
            lines.append("- Review top categories before adding new expenses this month")
        }

        return Array(lines.prefix(4))
    }

    private static func userProfile(adults: Int, children: Int) -> String {
        if adults == 0 && children == 0 {
            return "- Household: Not defined"
        }

        return [
            "- Adults: \(adults)",
            "- Children: \(children)"
        ].joined(separator: "\n")
    }

    private static func accountsBlock(_ accounts: [Account]) -> String {
        let lines = accounts
            .sorted { $0.createdAt < $1.createdAt }
            .map { account -> String in
                var details = "- \(account.name): \(account.type.label)"
                if account.type == .creditCard {
                    let cycleStart = account.billingStartDay.map(String.init) ?? "not defined"
                    let cycleEnd = account.billingCycleEndDay.map(String.init) ?? "not defined"
                    let closing = account.billingClosingDay.map(String.init) ?? "not defined"
                    let due = account.ccPaymentDueDay.map(String.init) ?? "not defined"
                    details += " · Billing cycle: day \(cycleStart) to day \(cycleEnd)"
                    details += " · Closing day \(closing)"
                    details += " · Payment due day \(due)"
                }
                if account.isDefault {
                    details += " · Default"
                }
                return details
            }

        return lines.isEmpty ? "- No accounts configured" : lines.joined(separator: "\n")
    }

    private static func previousMonthDiffs(
        current: MonthSnapshot,
        previous: MonthSnapshot,
        currencyCode: String
    ) -> [String] {
        let diffs = categoryDrivers(current: current, previous: previous)
            .prefix(3)
            .filter { abs($0.diff) >= 0.01 }

        if diffs.isEmpty {
            return ["- No relevant category differences found"]
        }

        return diffs.map { item in
            let direction = item.diff >= 0 ? "up" : "down"
            return "- \(item.category): \(direction) €\(amountValue(abs(item.diff)))"
        }
    }

    private static func categoryDrivers(
        current: MonthSnapshot,
        previous: MonthSnapshot
    ) -> [(category: String, diff: Double)] {
        let categories = Set(current.categoryTotals.keys).union(previous.categoryTotals.keys)
        return categories
            .map { category in
                let currentValue = current.categoryTotals[category] ?? 0
                let previousValue = previous.categoryTotals[category] ?? 0
                return (category, currentValue - previousValue)
            }
            .sorted { abs($0.diff) > abs($1.diff) }
    }

    private static func isFixedCostCategory(_ category: String) -> Bool {
        ["Moradia", "Saúde", "Educação", "Financeiro"].contains(category)
    }

    private static func amountValue(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    private static func validGoalName(_ name: String) -> String {
        validGoalNames.contains(name) ? name : "Moradia"
    }

    private static func categoryTotals(for transactions: [Transaction]) -> [String: Double] {
        var totals: [String: Double] = [:]
        for transaction in transactions {
            let categoryName = transactionRootCategoryName(transaction)
            totals[categoryName, default: 0] += transaction.amount
        }
        return totals
    }

    private static func transactionRootCategoryName(_ transaction: Transaction) -> String {
        if let category = transaction.category {
            return (category.parent ?? category).displayName
        }

        if let parent = transaction.subcategory?.parent {
            return parent.displayName
        }

        return t("insight.fallback.uncategorized")
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

    private static func transactionDescription(_ transaction: Transaction) -> String {
        transaction.placeName ?? transaction.subcategory?.displayName ?? transaction.category?.displayName ?? "Transaction"
    }

    private static func transactionAnalysisLine(
        _ transaction: Transaction,
        currencyCode: String,
        includeRecurrence: Bool
    ) -> String {
        var parts = [
            "- \(shortDateFormatter.string(from: transaction.date)) · \(transactionDescription(transaction)): €\(amountValue(transaction.amount))",
            "Account: \(accountSummary(transaction.account))"
        ]

        if let category = transaction.category {
            let rootCategory = category.parent ?? category
            parts.append("Category: \(rootCategory.displayName)")
        } else if let parent = transaction.subcategory?.parent {
            parts.append("Category: \(parent.displayName)")
        }

        if let subcategory = transaction.subcategory {
            parts.append("Subcategory: \(subcategory.displayName)")
        }

        parts.append("Status: \(transaction.isPaid ? "paid" : "pending")")

        if includeRecurrence {
            let recurrence = recurrenceLabel(for: transaction)
            if !recurrence.isEmpty {
                parts.append(recurrence.trimmingCharacters(in: CharacterSet(charactersIn: " ·")))
            }
        }

        parts.append("finaince://transaction/\(transaction.id.uuidString)")
        return parts.joined(separator: " · ")
    }

    private static func accountSummary(_ account: Account?) -> String {
        guard let account else { return "No account" }

        var summary = "\(account.name) (\(account.type.label))"
        if account.type == .creditCard {
            let cycleStart = account.billingStartDay.map(String.init) ?? "not defined"
            let cycleEnd = account.billingCycleEndDay.map(String.init) ?? "not defined"
            let closing = account.billingClosingDay.map(String.init) ?? "not defined"
            let due = account.ccPaymentDueDay.map(String.init) ?? "not defined"
            summary += ", billing cycle day \(cycleStart) to day \(cycleEnd)"
            summary += ", closing day \(closing)"
            summary += ", payment due day \(due)"
        }
        return summary
    }

    private static func recurrenceLabel(for transaction: Transaction) -> String {
        switch transaction.recurrenceType {
        case .none:
            return ""
        case .monthly:
            return " · monthly recurring"
        case .annual:
            return " · annual recurring"
        case .installment:
            if let index = transaction.installmentIndex, let total = transaction.installmentTotal {
                return " · installment \(index)/\(total)"
            }
            return " · installment"
        }
    }

    private static let validGoalNames: Set<String> = [
        "Restaurantes",
        "Moradia",
        "Supermercado",
        "Transporte",
        "Saúde",
        "Educação",
        "Lazer"
    ]

    private static let promptTemplate = """

    {{PROMPT_INTRO}}

    ### ANALYSIS OBJECTIVES

    - Identify overspending patterns
    - Highlight unnecessary or high-impact expenses
    - Suggest concrete actions to reduce spending
    - Point out risks for the next month
    - Guide what to adjust next

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

    These are financial data generated by the FinAInce app.

    MY FAMILY PROFILE:

    {{USER_PROFILE}}

    MY ACCOUNTS:

    {{ACCOUNTS_BLOCK}}

    MY GOALS:

    {{GOALS_BLOCK}}

    CURRENT MONTH:
    Total spent: €{{CURRENT_MONTH_TOTAL}}

    Top categories:

    {{CURRENT_MONTH_TOP_CATEGORIES}}

    All transactions:

    {{CURRENT_MONTH_ALL_TRANSACTIONS}}

    PREVIOUS MONTH:
    Total spent: €{{PREVIOUS_MONTH_TOTAL}}

    Key differences:

    - Current month is €{{MONTH_DIFFERENCE}} {{MONTH_DIRECTION}} than previous month
    {{PREVIOUS_MONTH_DIFFS}}

    Top categories:

    {{PREVIOUS_MONTH_TOP_CATEGORIES}}

    NEXT MONTH COMMITMENTS (ALREADY LOCKED EXPENSES):

    Planned expenses: €{{NEXT_MONTH_TOTAL}}

    Pending commitments:

    {{NEXT_MONTH_COMMITMENTS}}

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
    - Must include a clear € amount impact
    - Must be the highest-impact opportunity

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

    - Break down by source when possible

    -----

    ### RECOMMENDATIONS

    - Provide 3–5 actions total
    - Rank them by impact (highest savings first)
    - Each action must:
      - Use real data from the input
      - Be specific and actionable
      - Clearly state what to change

    -----

    ### RULES

    - Do NOT give generic advice
    - Do NOT invent data
    - Prefer concrete numbers over assumptions
    - Avoid repeating sentence structures
    - Avoid extreme or unrealistic suggestions

    -----

    ### RETURN TO APP

    Naturally reference FinAInce as the place where actions should be executed.

    Examples (use sparingly and naturally):
    - "Open FinAInce and review..."
    - "Go back to the app and adjust..."
    - "Inside FinAInce, you can..."

    -----

    ### FINAL NOTE

    Encourage the user to apply the changes, keep tracking expenses, and run a new analysis.

    Reinforce that:
    - The app is the control center
    - The AI is the advisor

    -----

    ### TASK

    Perform the financial analysis using all data provided.

    Generate a clear, structured and actionable response that follows all instructions above and aligns with the USER OBJECTIVE.
"""

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let fileMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "LLLL"
        return formatter
    }()
}
