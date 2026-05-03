import Foundation
import SwiftUI

struct SavingsOpportunity: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let action: String
    let estimatedSavings: Double
    let categoryName: String
    let currentSpend: Double
    let baselineSpend: Double
    let deltaAmount: Double
    let deltaPercent: Double
    let confidence: Double
    let topicKey: String
    let chatPrompt: String

    let icon: String = "banknote.fill"
    let color: Color = .green
}

enum SavingsOpportunityService {
    private static let absoluteThreshold = 50.0
    private static let percentageThreshold = 20.0
    private static let minimumOpportunity = 30.0
    private static let minimumDaysRemaining = 5
    private static let recentActivityWindow = 12
    private static let historicalMonths = 3

    static func computeOpportunities(
        transactions: [Transaction],
        month: Int,
        year: Int,
        currencyCode: String,
        maximumCount: Int = 2,
        now: Date = Date()
    ) -> [SavingsOpportunity] {
        let calendar = Calendar.current
        guard daysRemaining(in: month, year: year, from: now, calendar: calendar) > minimumDaysRemaining else {
            return []
        }

        let currentMonthExpenses = expenses(in: month, year: year, transactions: transactions, calendar: calendar)
        guard !currentMonthExpenses.isEmpty else { return [] }

        let groupedCurrent = Dictionary(grouping: currentMonthExpenses, by: categoryIdentity(for:))
        let candidates = groupedCurrent.compactMap { identity, categoryTransactions -> SavingsOpportunity? in
            guard let identity else { return nil }

            let currentSpend = categoryTransactions.reduce(0) { $0 + $1.amount }
            guard currentSpend > 0 else { return nil }

            let historicalTotals = (1...historicalMonths).map { offset in
                historicalCategorySpend(
                    transactions: transactions,
                    categoryKey: identity.key,
                    monthOffset: -offset,
                    referenceMonth: month,
                    referenceYear: year,
                    calendar: calendar
                )
            }

            let lastMonthSpend = historicalTotals.first ?? 0
            let nonZeroHistory = historicalTotals.filter { $0 > 0 }
            guard lastMonthSpend > 0 || nonZeroHistory.count >= 2 else { return nil }

            let averageHistoricalSpend = historicalTotals.reduce(0, +) / Double(historicalTotals.count)
            let baselineSpend = max(lastMonthSpend, averageHistoricalSpend)
            guard baselineSpend > 0 else { return nil }

            let excess = currentSpend - baselineSpend
            guard excess > minimumOpportunity else { return nil }

            let percentIncrease = (excess / baselineSpend) * 100
            guard excess >= absoluteThreshold || percentIncrease >= percentageThreshold else { return nil }

            let recentTransactions = categoryTransactions.filter {
                $0.date >= (calendar.date(byAdding: .day, value: -recentActivityWindow, to: now) ?? .distantPast)
            }
            guard !recentTransactions.isEmpty else { return nil }

            let actionPlan = buildActionPlan(
                categoryName: identity.name,
                estimatedSavings: excess,
                recentTransactions: recentTransactions
            )
            guard let actionPlan else { return nil }

            let reasonUsesLastMonth = lastMonthSpend >= averageHistoricalSpend
            let bodyKey = reasonUsesLastMonth
                ? "ai.opportunities.cardBody.lastMonth"
                : "ai.opportunities.cardBody.average"

            let confidence = confidenceScore(
                historicalTotals: historicalTotals,
                recentTransactions: recentTransactions,
                excess: excess,
                percentIncrease: percentIncrease
            )
            guard confidence >= 0.68 else { return nil }

            let title = t("ai.opportunities.cardTitle", excess.asCurrency(currencyCode))
            let body = t(
                bodyKey,
                identity.name,
                baselineSpend.asCurrency(currencyCode)
            )

            return SavingsOpportunity(
                title: title,
                body: body,
                action: actionPlan.userText,
                estimatedSavings: excess,
                categoryName: identity.name,
                currentSpend: currentSpend,
                baselineSpend: baselineSpend,
                deltaAmount: excess,
                deltaPercent: percentIncrease,
                confidence: confidence,
                topicKey: "savings-opportunity:\(identity.key)",
                chatPrompt: buildPrompt(
                    categoryName: identity.name,
                    currentSpend: currentSpend,
                    baselineSpend: baselineSpend,
                    estimatedSavings: excess,
                    percentIncrease: percentIncrease,
                    reasonUsesLastMonth: reasonUsesLastMonth,
                    actionPlan: actionPlan,
                    currencyCode: currencyCode
                )
            )
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.deltaAmount == rhs.deltaAmount {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.deltaAmount > rhs.deltaAmount
            }
            .prefix(maximumCount)
            .map { $0 }
    }

    private struct CategoryIdentity: Hashable {
        let key: String
        let name: String
    }

    private struct ActionPlan {
        let userText: String
        let promptText: String
    }

    private static func expenses(
        in month: Int,
        year: Int,
        transactions: [Transaction],
        calendar: Calendar
    ) -> [Transaction] {
        transactions.filter {
            $0.type == .expense &&
            categoryIdentity(for: $0) != nil &&
            matches(month: month, year: year, date: $0.date, calendar: calendar)
        }
    }

    private static func historicalCategorySpend(
        transactions: [Transaction],
        categoryKey: String,
        monthOffset: Int,
        referenceMonth: Int,
        referenceYear: Int,
        calendar: Calendar
    ) -> Double {
        guard
            let referenceDate = calendar.date(from: DateComponents(year: referenceYear, month: referenceMonth, day: 1)),
            let targetDate = calendar.date(byAdding: .month, value: monthOffset, to: referenceDate)
        else {
            return 0
        }

        let targetMonth = calendar.component(.month, from: targetDate)
        let targetYear = calendar.component(.year, from: targetDate)
        return transactions
            .filter {
                $0.type == .expense &&
                categoryIdentity(for: $0)?.key == categoryKey &&
                matches(month: targetMonth, year: targetYear, date: $0.date, calendar: calendar)
            }
            .reduce(0) { $0 + $1.amount }
    }

    private static func categoryIdentity(for transaction: Transaction) -> CategoryIdentity? {
        guard let category = transaction.category?.rootCategory ?? transaction.category else { return nil }
        return CategoryIdentity(
            key: category.systemKey ?? category.name,
            name: category.displayName
        )
    }

    private static func matches(month: Int, year: Int, date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.month, .year], from: date)
        return components.month == month && components.year == year
    }

    private static func daysRemaining(in month: Int, year: Int, from now: Date, calendar: Calendar) -> Int {
        let currentComponents = calendar.dateComponents([.month, .year], from: now)
        guard currentComponents.month == month, currentComponents.year == year else { return 0 }
        guard
            let range = calendar.range(of: .day, in: .month, for: now)
        else {
            return 0
        }
        let currentDay = calendar.component(.day, from: now)
        return max(0, range.count - currentDay)
    }

    private static func buildActionPlan(
        categoryName: String,
        estimatedSavings: Double,
        recentTransactions: [Transaction]
    ) -> ActionPlan? {
        let averageTicket = recentTransactions.reduce(0) { $0 + $1.amount } / Double(max(recentTransactions.count, 1))
        guard averageTicket > 0 else { return nil }

        let avoidedPurchases = min(4, max(1, Int((estimatedSavings / averageTicket).rounded(.toNearestOrAwayFromZero))))
        let userText: String
        let promptText: String

        if recentTransactions.count >= 2 {
            userText = t("ai.opportunities.cardAction.reducePurchases", avoidedPurchases, categoryName)
            promptText = "Estimate a plan around reducing about \(avoidedPurchases) purchases in \(categoryName) before month end."
        } else {
            userText = t("ai.opportunities.cardAction.pauseCategory", categoryName)
            promptText = "Focus on pausing new spending in \(categoryName) for the next few days to recover this excess."
        }

        return ActionPlan(userText: userText, promptText: promptText)
    }

    private static func confidenceScore(
        historicalTotals: [Double],
        recentTransactions: [Transaction],
        excess: Double,
        percentIncrease: Double
    ) -> Double {
        let historyScore = min(1, Double(historicalTotals.filter { $0 > 0 }.count) / 3)
        let activityScore = min(1, Double(recentTransactions.count) / 4)
        let absoluteScore = min(1, excess / 200)
        let percentScore = min(1, percentIncrease / 60)
        return (historyScore * 0.30) + (activityScore * 0.20) + (absoluteScore * 0.30) + (percentScore * 0.20)
    }

    private static func buildPrompt(
        categoryName: String,
        currentSpend: Double,
        baselineSpend: Double,
        estimatedSavings: Double,
        percentIncrease: Double,
        reasonUsesLastMonth: Bool,
        actionPlan: ActionPlan,
        currencyCode: String
    ) -> String {
        let baselineLabel = reasonUsesLastMonth ? "last month" : "recent average"

        return """
        Savings Opportunity

        Goal:
        Help the user understand one concrete, realistic, actionable savings opportunity for this month.

        Opportunity detected:
        - Category: \(categoryName)
        - Current month spending: \(currentSpend.asCurrency(currencyCode))
        - Baseline (\(baselineLabel)): \(baselineSpend.asCurrency(currencyCode))
        - Estimated avoidable excess: \(estimatedSavings.asCurrency(currencyCode))
        - Increase vs baseline: \(Int(percentIncrease.rounded()))%
        - Suggested action: \(actionPlan.promptText)

        Your task:
        1. Explain clearly where this savings is coming from.
        2. Explain why this category is above normal right now.
        3. Turn the suggested action into a practical plan for the rest of this month.
        4. Keep the recommendation specific, personalized, and realistic.

        Rules:
        - Do not give generic advice.
        - Mention the concrete savings amount.
        - Mention the user action required to capture that amount.
        - Keep the answer concise and actionable.
        """
    }
}
