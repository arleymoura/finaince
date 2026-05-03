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

@MainActor
enum SavingsOpportunityService {
    private static let absoluteThreshold = 50.0
    private static let percentageThreshold = 20.0
    private static let minimumOpportunity = 30.0
    private static let minimumDaysRemaining = 5
    private static let recentActivityWindow = 12
    private static let historicalMonths = 3
    private static let dominantTransactionShareThreshold = 0.75

    private static func debugLog(_ message: String) {
#if DEBUG
        print("[SavingsOpportunity] \(message)")
#endif
    }

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
            debugLog("Skipped computation: not enough days left in \(month)/\(year).")
            return []
        }

        let currentMonthExpenses = expenses(in: month, year: year, transactions: transactions, calendar: calendar)
        guard !currentMonthExpenses.isEmpty else {
            debugLog("Skipped computation: no current month expenses found.")
            return []
        }

        debugLog("Starting computation with \(currentMonthExpenses.count) current month expenses.")

        let groupedCurrent = Dictionary(grouping: currentMonthExpenses, by: categoryIdentity(for:))
        let candidates = groupedCurrent.compactMap { identity, categoryTransactions -> SavingsOpportunity? in
            guard let identity else {
                debugLog("Discarded transactions without category identity.")
                return nil
            }

            let currentSpend = categoryTransactions.reduce(0) { $0 + $1.amount }
            guard currentSpend > 0 else {
                debugLog("Discarded \(identity.name): current spend is zero.")
                return nil
            }

            debugLog("Evaluating \(identity.name): currentSpend=\(currentSpend)")

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
            guard lastMonthSpend > 0 || nonZeroHistory.count >= 2 else {
                debugLog("Discarded \(identity.name): insufficient history. lastMonth=\(lastMonthSpend), nonZeroHistory=\(nonZeroHistory.count)")
                return nil
            }

            let averageHistoricalSpend = historicalTotals.reduce(0, +) / Double(historicalTotals.count)
            let baselineSpend = max(lastMonthSpend, averageHistoricalSpend)
            guard baselineSpend > 0 else {
                debugLog("Discarded \(identity.name): baseline is zero.")
                return nil
            }

            let excess = currentSpend - baselineSpend
            guard excess > minimumOpportunity else {
                debugLog("Discarded \(identity.name): excess \(excess) below minimum \(minimumOpportunity).")
                return nil
            }

            let percentIncrease = (excess / baselineSpend) * 100
            guard excess >= absoluteThreshold || percentIncrease >= percentageThreshold else {
                debugLog("Discarded \(identity.name): excess \(excess) and percent \(percentIncrease) below thresholds.")
                return nil
            }

            let recentTransactions = categoryTransactions.filter {
                $0.date >= (calendar.date(byAdding: .day, value: -recentActivityWindow, to: now) ?? .distantPast)
            }
            guard !recentTransactions.isEmpty else {
                debugLog("Discarded \(identity.name): no recent transactions in last \(recentActivityWindow) days.")
                return nil
            }

            let dominantTransactionShare = (categoryTransactions.map(\.amount).max() ?? 0) / max(currentSpend, 1)
            let hasEnoughOngoingBehavior = recentTransactions.count >= 2 || categoryTransactions.count >= 3
            guard hasEnoughOngoingBehavior || dominantTransactionShare < dominantTransactionShareThreshold else {
                debugLog("Discarded \(identity.name): looks like isolated purchase. dominantShare=\(dominantTransactionShare), recent=\(recentTransactions.count), total=\(categoryTransactions.count)")
                return nil
            }

            let actionPlan = buildActionPlan(
                categoryKey: identity.key,
                categoryName: identity.name,
                estimatedSavings: excess,
                recentTransactions: recentTransactions
            )
            guard let actionPlan else {
                debugLog("Discarded \(identity.name): failed to build action plan.")
                return nil
            }

            let reasonUsesLastMonth = lastMonthSpend >= averageHistoricalSpend
            let bodyKey = reasonUsesLastMonth
                ? "ai.opportunities.cardBody.lastMonth"
                : "ai.opportunities.cardBody.average"

            let confidence = confidenceScore(
                historicalTotals: historicalTotals,
                recentTransactions: recentTransactions,
                excess: excess,
                percentIncrease: percentIncrease,
                dominantTransactionShare: dominantTransactionShare
            )
            guard confidence >= 0.68 else {
                debugLog("Discarded \(identity.name): confidence \(confidence) below threshold.")
                return nil
            }

            let title = t("ai.opportunities.cardTitle", excess.asCurrency(currencyCode))
            let body = t(
                bodyKey,
                identity.name,
                baselineSpend.asCurrency(currencyCode)
            )

            debugLog("Accepted \(identity.name): savings=\(excess), baseline=\(baselineSpend), percent=\(percentIncrease), confidence=\(confidence)")

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
        let contextLines: [String]
    }

    private struct MerchantSummary {
        let name: String
        let count: Int
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
        guard let category = transaction.subcategory ?? transaction.category else { return nil }
        let parentKey = category.parent?.systemKey ?? category.parent?.name ?? category.rootCategory.systemKey ?? category.rootCategory.name
        let ownKey = category.systemKey ?? category.name
        return CategoryIdentity(
            key: "\(parentKey)::\(ownKey)",
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
        categoryKey: String,
        categoryName: String,
        estimatedSavings: Double,
        recentTransactions: [Transaction]
    ) -> ActionPlan? {
        let averageTicket = recentTransactions.reduce(0) { $0 + $1.amount } / Double(max(recentTransactions.count, 1))
        guard averageTicket > 0 else { return nil }

        let normalizedCategory = normalize(categoryKey + " " + categoryName)
        let reducedActions = max(1, Int((estimatedSavings / averageTicket).rounded(.toNearestOrAwayFromZero)))
        let cappedActions = min(4, reducedActions)
        let merchantSummary = dominantMerchant(in: recentTransactions)
        let userText: String
        let promptText: String
        let contextLines: [String]

        if normalizedCategory.contains("restaurant") || normalizedCategory.contains("delivery") || normalizedCategory.contains("food") || normalizedCategory.contains("aliment") {
            if let merchantSummary {
                userText = t("ai.opportunities.cardAction.foodMerchant", merchantSummary.name, merchantSummary.count, cappedActions)
                promptText = "Suggest how the user can cut about \(cappedActions) restaurant or delivery orders from \(merchantSummary.name), which appeared \(merchantSummary.count) times recently."
                contextLines = [
                    "Recent repeated merchant: \(merchantSummary.name)",
                    "Recent merchant frequency: \(merchantSummary.count) transactions"
                ]
            } else {
                userText = t("ai.opportunities.cardAction.food", cappedActions)
                promptText = "Suggest how the user can cut about \(cappedActions) restaurant or delivery orders this month."
                contextLines = [
                    "Recent category frequency: \(recentTransactions.count) transactions"
                ]
            }
        } else if normalizedCategory.contains("transport") || normalizedCategory.contains("uber") || normalizedCategory.contains("fuel") || normalizedCategory.contains("gas") {
            if let merchantSummary {
                userText = t("ai.opportunities.cardAction.transportMerchant", merchantSummary.name, merchantSummary.count)
                promptText = "Suggest how the user can reduce discretionary rides or transport costs tied to \(merchantSummary.name), which appeared \(merchantSummary.count) times recently."
                contextLines = [
                    "Recent repeated merchant: \(merchantSummary.name)",
                    "Recent merchant frequency: \(merchantSummary.count) transactions"
                ]
            } else {
                userText = t("ai.opportunities.cardAction.transport", categoryName)
                promptText = "Suggest how the user can reduce discretionary rides or transport costs in \(categoryName) for the rest of the month."
                contextLines = [
                    "Recent category frequency: \(recentTransactions.count) transactions"
                ]
            }
        } else if normalizedCategory.contains("shop") || normalizedCategory.contains("compra") || normalizedCategory.contains("store") || normalizedCategory.contains("retail") {
            if let merchantSummary {
                userText = t("ai.opportunities.cardAction.shoppingMerchant", merchantSummary.name, cappedActions)
                promptText = "Suggest how the user can postpone about \(cappedActions) non-essential purchases from \(merchantSummary.name) until next month."
                contextLines = [
                    "Recent repeated merchant: \(merchantSummary.name)",
                    "Recent merchant frequency: \(merchantSummary.count) transactions"
                ]
            } else {
                userText = t("ai.opportunities.cardAction.shopping", categoryName)
                promptText = "Suggest how the user can postpone non-essential purchases in \(categoryName) until next month."
                contextLines = [
                    "Recent category frequency: \(recentTransactions.count) transactions"
                ]
            }
        } else if normalizedCategory.contains("subscription") || normalizedCategory.contains("stream") || normalizedCategory.contains("assin") {
            if let merchantSummary {
                userText = t("ai.opportunities.cardAction.subscriptionMerchant", merchantSummary.name)
                promptText = "Suggest how the user can pause, cancel, or defer charges from \(merchantSummary.name) this month."
                contextLines = [
                    "Recent repeated merchant: \(merchantSummary.name)",
                    "Recent merchant frequency: \(merchantSummary.count) transactions"
                ]
            } else {
                userText = t("ai.opportunities.cardAction.subscription", categoryName)
                promptText = "Suggest how the user can pause, cancel, or defer charges in \(categoryName) this month."
                contextLines = [
                    "Recent category frequency: \(recentTransactions.count) transactions"
                ]
            }
        } else if let merchantSummary {
            userText = t("ai.opportunities.cardAction.reduceMerchant", merchantSummary.name, merchantSummary.count, cappedActions)
            promptText = "Estimate a plan around reducing about \(cappedActions) purchases from \(merchantSummary.name), which appeared \(merchantSummary.count) times recently."
            contextLines = [
                "Recent repeated merchant: \(merchantSummary.name)",
                "Recent merchant frequency: \(merchantSummary.count) transactions"
            ]
        } else if recentTransactions.count >= 2 {
            userText = t("ai.opportunities.cardAction.reduceFrequency", recentTransactions.count, cappedActions, categoryName)
            promptText = "Estimate a plan around reducing about \(cappedActions) purchases in \(categoryName), where the user already had \(recentTransactions.count) recent transactions."
            contextLines = [
                "Recent category frequency: \(recentTransactions.count) transactions"
            ]
        } else {
            userText = t("ai.opportunities.cardAction.pauseCategory", categoryName)
            promptText = "Focus on pausing new spending in \(categoryName) for the next few days to recover this excess."
            contextLines = []
        }

        return ActionPlan(userText: userText, promptText: promptText, contextLines: contextLines)
    }

    private static func confidenceScore(
        historicalTotals: [Double],
        recentTransactions: [Transaction],
        excess: Double,
        percentIncrease: Double,
        dominantTransactionShare: Double
    ) -> Double {
        let historyScore = min(1, Double(historicalTotals.filter { $0 > 0 }.count) / 3)
        let activityScore = min(1, Double(recentTransactions.count) / 4)
        let absoluteScore = min(1, excess / 200)
        let percentScore = min(1, percentIncrease / 60)
        let concentrationPenalty = max(0, dominantTransactionShare - 0.55) * 0.35
        return ((historyScore * 0.30) + (activityScore * 0.20) + (absoluteScore * 0.30) + (percentScore * 0.20)) - concentrationPenalty
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
    }

    private static func dominantMerchant(in transactions: [Transaction]) -> MerchantSummary? {
        let merchants = transactions.compactMap { transaction -> String? in
            let rawValue = transaction.placeName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let rawValue, !rawValue.isEmpty {
                return rawValue
            }
            let noteValue = transaction.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let noteValue, !noteValue.isEmpty else { return nil }
            return noteValue.count > 36 ? String(noteValue.prefix(36)) : noteValue
        }
        guard merchants.count >= 2 else { return nil }

        let grouped = Dictionary(grouping: merchants, by: { normalize($0) })
        guard
            let best = grouped.max(by: { lhs, rhs in lhs.value.count < rhs.value.count }),
            let representative = best.value.first
        else {
            return nil
        }

        let count = best.value.count
        let share = Double(count) / Double(max(merchants.count, 1))
        guard count >= 2, share >= 0.5 else { return nil }
        return MerchantSummary(name: representative, count: count)
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
        let contextBlock = actionPlan.contextLines
            .map { "- \($0)" }
            .joined(separator: "\n")
        let opportunityLines = [
            "- Category: \(categoryName)",
            "- Current month spending: \(currentSpend.asCurrency(currencyCode))",
            "- Baseline (\(baselineLabel)): \(baselineSpend.asCurrency(currencyCode))",
            "- Estimated avoidable excess: \(estimatedSavings.asCurrency(currencyCode))",
            "- Increase vs baseline: \(Int(percentIncrease.rounded()))%",
            "- Suggested action: \(actionPlan.promptText)"
        ].joined(separator: "\n")
        let behavioralSection = contextBlock.isEmpty ? "" : "\nBehavioral context:\n\(contextBlock)"

        return """
        Savings Opportunity

        Goal:
        Help the user understand one concrete, realistic, actionable savings opportunity for this month.

        Opportunity detected:
        \(opportunityLines)\(behavioralSection)

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
