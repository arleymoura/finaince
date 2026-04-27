import Foundation
import SwiftData
import SwiftUI

// MARK: - InsightEngine

struct InsightEngine {

    private static var sessionHistory: [String: Date] = [:]
    private static let sessionRepeatWindow: TimeInterval = 60 * 30
    private static let maxInsightsToShow = 3

    // MARK: - Public API

    static func compute(
        transactions: [Transaction],
        accounts: [Account] = [],
        goals: [Goal] = [],
        month: Int,
        year: Int,
        currencyCode: String,
        selectedAccountId: UUID? = nil
    ) -> [Insight] {
        let context = InsightContext(
            transactions: transactions,
            accounts: accounts,
            goals: goals,
            month: month,
            year: year,
            currencyCode: currencyCode,
            selectedAccountId: selectedAccountId
        )

        guard !context.scopedTransactions.isEmpty || !goals.isEmpty else { return [] }

        var candidates: [Insight] = []

        candidates.appendIfPresent(goalRiskInsight(context))
        candidates.appendIfPresent(endOfMonthProjectionInsight(context))
        candidates.appendIfPresent(spendingPaceInsight(context))
        candidates.appendIfPresent(subscriptionUnusedInsight(context))
        candidates.appendIfPresent(abnormalTransactionInsight(context))
        // Disabled for now: cash-flow projection needs income vs expense modeling to avoid misleading balance insights.
        // candidates.appendIfPresent(cashFlowProjectionInsight(context))
        candidates.appendIfPresent(categoryTrendUpInsight(context))
        candidates.appendIfPresent(categoryOverBaselineInsight(context))
        candidates.appendIfPresent(monthComparisonInsight(context))
        candidates.appendIfPresent(recurringPriceChangeInsight(context))
        candidates.appendIfPresent(topCategoryInsight(context))
        candidates.appendIfPresent(spendingConcentrationInsight(context))
        candidates.appendIfPresent(avgTicketIncreaseInsight(context))
        candidates.appendIfPresent(billDueSoonInsight(context))
        candidates.appendIfPresent(installmentsInsight(context))
        candidates.appendIfPresent(streakSavingInsight(context))
        candidates.appendIfPresent(behaviorPatternInsight(context))

        let selected = selectInsights(from: candidates)
        rememberShownInsights(selected)
        return selected
    }

    // MARK: - Selection

    private static func selectInsights(from candidates: [Insight]) -> [Insight] {
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.title < rhs.title
            }
            return lhs.score > rhs.score
        }

        var selected: [Insight] = []
        var usedKinds = Set<InsightType>()
        var usedTopics = Set<String>()

        func canAdd(_ insight: Insight) -> Bool {
            !usedKinds.contains(insight.kind) && !usedTopics.contains(insight.topicKey)
        }

        func add(_ insight: Insight) {
            selected.append(insight)
            usedKinds.insert(insight.kind)
            usedTopics.insert(insight.topicKey)
        }

        if let alert = sorted.first(where: { $0.sentiment == .alert && canAdd($0) }) {
            add(alert)
        }

        if let opportunity = sorted.first(where: { $0.sentiment == .opportunity && canAdd($0) }) {
            add(opportunity)
        }

        for insight in sorted where selected.count < maxInsightsToShow {
            guard canAdd(insight) else { continue }
            add(insight)
        }

        return Array(selected.prefix(maxInsightsToShow))
    }

    private static func rememberShownInsights(_ insights: [Insight]) {
        let now = Date()
        sessionHistory = sessionHistory.filter { now.timeIntervalSince($0.value) < sessionRepeatWindow }

        for insight in insights {
            sessionHistory["kind:\(String(describing: insight.kind))"] = now
            sessionHistory["topic:\(insight.topicKey)"] = now
        }
    }

    // MARK: - Candidate builders

    private static func recurringPriceChangeInsight(_ context: InsightContext) -> Insight? {
        let monthlyTx = context.currentMonthExpenses.filter {
            $0.recurrenceType == .monthly && $0.date <= context.now
        }

        for tx in monthlyTx.sorted(by: { $0.amount > $1.amount }) {
            let previous = context.scopedTransactions
                .filter { candidate in
                    guard candidate.id != tx.id,
                          candidate.type == .expense,
                          candidate.recurrenceType == .monthly,
                          candidate.date < tx.date else { return false }
                    if let groupId = tx.installmentGroupId {
                        return candidate.installmentGroupId == groupId
                    }
                    return merchantKey(candidate) == merchantKey(tx)
                }
                .sorted { $0.date > $1.date }
                .first

            guard let previous, previous.amount > 0 else { continue }

            let delta = tx.amount - previous.amount
            let percent = abs(delta / previous.amount) * 100
            guard percent >= 3 else { continue }

            let name = tx.placeName ?? tx.category?.displayName ?? t("insight.fallback.recurringExpense")
            let isIncrease = delta > 0

            return makeInsight(
                kind: .priceChange,
                title: isIncrease
                    ? t("insight.priceChange.increase.title", name)
                    : t("insight.priceChange.decrease.title", name),
                body: t("insight.priceChange.body", Int(percent.rounded())),
                icon: isIncrease ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                color: isIncrease ? .red : .green,
                sentiment: isIncrease ? .alert : .opportunity,
                topicKey: "price:\(merchantKey(tx))",
                amount: abs(delta),
                percentage: percent,
                category: tx.category?.displayName,
                merchant: tx.placeName,
                impactAmount: tx.amount,
                deviationPercent: percent,
                urgency: 35,
                basePriority: 80,
                currencyCode: context.currencyCode,
                chatPrompt: t(
                    "insight.priceChange.prompt",
                    name,
                    Int(percent.rounded()),
                    tx.amount.asCurrency(context.currencyCode)
                )
            )
        }

        return nil
    }

    private static func monthComparisonInsight(_ context: InsightContext) -> Insight? {
        guard context.previousMonthPaid > 0, context.currentMonthPaid > 0 else { return nil }

        let delta = context.currentMonthPaid - context.previousMonthPaid
        let percent = abs(delta / context.previousMonthPaid) * 100
        guard percent >= 5 else { return nil }

        let isIncrease = delta > 0

        return makeInsight(
            kind: .monthComparison,
            title: isIncrease ? t("insight.monthComparison.up.title") : t("insight.monthComparison.down.title"),
            body: t("insight.monthComparison.body", Int(percent.rounded())),
            icon: isIncrease ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
            color: isIncrease ? .red : .green,
            sentiment: isIncrease ? .alert : .opportunity,
            topicKey: "month-comparison",
            amount: context.currentMonthPaid,
            percentage: percent,
            category: nil,
            merchant: nil,
            impactAmount: abs(delta),
            deviationPercent: percent,
            urgency: 40,
            basePriority: 90,
            currencyCode: context.currencyCode,
            chatPrompt: t(
                "insight.monthComparison.prompt",
                context.currentMonthPaid.asCurrency(context.currencyCode),
                context.previousMonthPaid.asCurrency(context.currencyCode),
                Int(percent.rounded())
            )
        )
    }

    private static func spendingPaceInsight(_ context: InsightContext) -> Insight? {
        guard context.isCurrentMonth, context.elapsedMonthRatio > 0 else { return nil }

        let projected = context.projectedEndOfMonthTotal
        guard projected > 0 else { return nil }

        let paidRatio = context.currentMonthPaid / projected
        let ratio = paidRatio / context.elapsedMonthRatio
        guard ratio > 1.25 else { return nil }

        return makeInsight(
            kind: .spendingPace,
            title: t("insight.spendingPace.title"),
            body: t(
                "insight.spendingPace.body",
                Int((paidRatio * 100).rounded()),
                Int((context.elapsedMonthRatio * 100).rounded())
            ),
            icon: "speedometer",
            color: .orange,
            sentiment: .alert,
            topicKey: "spending-pace",
            amount: projected,
            percentage: (ratio - 1) * 100,
            category: nil,
            merchant: nil,
            impactAmount: projected - context.currentMonthPaid,
            deviationPercent: (ratio - 1) * 100,
            urgency: 80,
            basePriority: 150,
            currencyCode: context.currencyCode,
            chatPrompt: t("insight.spendingPace.prompt", projected.asCurrency(context.currencyCode))
        )
    }

    private static func subscriptionUnusedInsight(_ context: InsightContext) -> Insight? {
        let paidMonthly = context.pastExpenses.filter {
            $0.recurrenceType == .monthly && $0.isPaid
        }

        let grouped = Dictionary(grouping: paidMonthly) { transaction in
            merchantKey(transaction)
        }
        var flagged: [(name: String, amount: Double)] = []

        for (key, values) in grouped {
            guard values.count >= 3 else { continue }
            let amounts = values.map(\.amount)
            let average = amounts.reduce(0, +) / Double(amounts.count)
            guard average > 0 else { continue }

            let maxDeviation = amounts.map { abs($0 - average) / average }.max() ?? 1
            guard maxDeviation <= 0.05 else { continue }

            let interactionSignals = values.reduce(0) { partialResult, tx in
                let notesSignal = (tx.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 1 : 0
                let receiptSignal = (tx.receiptAttachments ?? []).isEmpty ? 0 : 1
                let placeSignal = tx.placeGoogleId == nil ? 0 : 1
                return partialResult + notesSignal + receiptSignal + placeSignal
            }
            guard interactionSignals <= values.count else { continue }

            let name = values.sorted { $0.date > $1.date }.first?.placeName
                ?? values.first?.category?.displayName
                ?? key.capitalized
            flagged.append((name: name, amount: average))
        }

        guard !flagged.isEmpty else { return nil }

        let total = flagged.reduce(0) { $0 + $1.amount }
        let count = flagged.count

        return makeInsight(
            kind: .subscriptionUnused,
            title: t(count > 1 ? "insight.subscriptionUnused.titlePlural" : "insight.subscriptionUnused.titleSingular", count),
            body: t("insight.subscriptionUnused.body", total.asCurrency(context.currencyCode)),
            icon: "rectangle.stack.badge.minus",
            color: .orange,
            sentiment: .alert,
            topicKey: "subscriptions-unused",
            amount: total,
            percentage: nil,
            category: nil,
            merchant: flagged.first?.name,
            impactAmount: total,
            deviationPercent: nil,
            urgency: 55,
            basePriority: 130,
            currencyCode: context.currencyCode,
            chatPrompt: t(
                "insight.subscriptionUnused.prompt",
                count,
                total.asCurrency(context.currencyCode)
            )
        )
    }

    private static func endOfMonthProjectionInsight(_ context: InsightContext) -> Insight? {
        guard context.isCurrentMonth, context.elapsedMonthRatio > 0, context.currentMonthPaid > 0 else { return nil }

        let projected = context.projectedEndOfMonthTotal
        guard projected > 0 else { return nil }

        let reference = max(context.previousMonthPaid, 1)
        let delta = projected - context.previousMonthPaid
        let percent = abs(delta / reference) * 100
        guard percent >= 8 || context.currentMonthPaid > 0 else { return nil }

        let isHigher = delta > 0

        return makeInsight(
            kind: .endOfMonthProjection,
            title: isHigher ? t("insight.endOfMonthProjection.high.title") : t("insight.endOfMonthProjection.low.title"),
            body: t("insight.endOfMonthProjection.body", projected.asCurrency(context.currencyCode)),
            icon: "chart.line.uptrend.xyaxis",
            color: isHigher ? .red : .green,
            sentiment: isHigher ? .alert : .opportunity,
            topicKey: "end-month-projection",
            amount: projected,
            percentage: percent,
            category: nil,
            merchant: nil,
            impactAmount: abs(delta),
            deviationPercent: percent,
            urgency: 85,
            basePriority: 160,
            currencyCode: context.currencyCode,
            chatPrompt: t(
                "insight.endOfMonthProjection.prompt",
                projected.asCurrency(context.currencyCode),
                context.previousMonthPaid.asCurrency(context.currencyCode)
            )
        )
    }

    private static func abnormalTransactionInsight(_ context: InsightContext) -> Insight? {
        let currentTransactions = context.currentMonthPaidExpenses
            .sorted { $0.amount > $1.amount }

        let historicalAverageTicket = averageTicket(for: context.previousPaidExpenses)
        var bestMatch: (tx: Transaction, percent: Double, amount: Double, title: String, body: String, prompt: String)?

        for tx in currentTransactions {
            guard let merchant = tx.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !merchant.isEmpty else { continue }

            let history = context.pastExpenses.filter {
                $0.id != tx.id && merchantKey($0) == merchantKey(tx) && $0.isPaid && $0.date < tx.date
            }

            if history.count >= 2 {
                let average = history.reduce(0) { $0 + $1.amount } / Double(history.count)
                guard average > 0 else { continue }
                let percent = ((tx.amount - average) / average) * 100
                guard tx.amount > average * 1.8, percent > 40 else { continue }

                let body = t(
                    "insight.abnormalTransaction.known.body",
                    tx.amount.asCurrency(context.currencyCode),
                    Int(percent.rounded())
                )
                let prompt = t(
                    "insight.abnormalTransaction.known.prompt",
                    merchant,
                    tx.amount.asCurrency(context.currencyCode),
                    Int(percent.rounded())
                )

                if bestMatch == nil || percent > (bestMatch?.percent ?? 0) {
                    bestMatch = (tx, percent, tx.amount, t("insight.abnormalTransaction.known.title", merchant), body, prompt)
                }
            } else if tx.amount > max(100, historicalAverageTicket * 2.5) {
                let percent = historicalAverageTicket > 0 ? ((tx.amount - historicalAverageTicket) / historicalAverageTicket) * 100 : 120
                let body = t("insight.abnormalTransaction.first.body", merchant, tx.amount.asCurrency(context.currencyCode))
                let prompt = t(
                    "insight.abnormalTransaction.first.prompt",
                    merchant,
                    tx.amount.asCurrency(context.currencyCode)
                )

                if bestMatch == nil || tx.amount > (bestMatch?.amount ?? 0) {
                    bestMatch = (tx, percent, tx.amount, t("insight.abnormalTransaction.first.title", merchant), body, prompt)
                }
            }
        }

        guard let bestMatch else { return nil }

        return makeInsight(
            kind: .abnormalTransaction,
            title: bestMatch.title,
            body: bestMatch.body,
            icon: "exclamationmark.triangle.fill",
            color: .orange,
            sentiment: .alert,
            topicKey: "abnormal:\(merchantKey(bestMatch.tx))",
            amount: bestMatch.amount,
            percentage: bestMatch.percent,
            category: bestMatch.tx.category?.displayName,
            merchant: bestMatch.tx.placeName,
            impactAmount: bestMatch.amount,
            deviationPercent: bestMatch.percent,
            urgency: 75,
            basePriority: 120,
            currencyCode: context.currencyCode,
            chatPrompt: bestMatch.prompt
        )
    }

    private static func categoryTrendUpInsight(_ context: InsightContext) -> Insight? {
        var best: (categoryKey: String, categoryName: String, amount: Double, growth: Double)?

        for category in context.distinctCategories {
            let current = categoryTotal(category.key, in: context.currentMonthPaidExpenses)
            let previous = categoryTotal(category.key, in: context.monthExpenses(offset: -1).filter(\.isPaid))
            let older = categoryTotal(category.key, in: context.monthExpenses(offset: -2).filter(\.isPaid))

            guard older > 0, previous > older, current > previous else { continue }

            let growth = ((current - older) / older) * 100
            guard growth >= 15 else { continue }

            if best == nil || growth > (best?.growth ?? 0) {
                best = (category.key, category.name, current, growth)
            }
        }

        guard let best else { return nil }

        return makeInsight(
            kind: .categoryTrendUp,
            title: t("insight.categoryTrendUp.title", best.categoryName),
            body: t("insight.categoryTrendUp.body", Int(best.growth.rounded())),
            icon: "chart.line.uptrend.xyaxis.circle.fill",
            color: .orange,
            sentiment: .alert,
            topicKey: "trend:\(best.categoryKey)",
            amount: best.amount,
            percentage: best.growth,
            category: best.categoryName,
            merchant: nil,
            impactAmount: best.amount,
            deviationPercent: best.growth,
            urgency: 60,
            basePriority: 110,
            currencyCode: context.currencyCode,
            chatPrompt: t(
                "insight.categoryTrendUp.prompt",
                best.categoryName,
                Int(best.growth.rounded())
            )
        )
    }

    private static func goalRiskInsight(_ context: InsightContext) -> Insight? {
        guard !context.goals.isEmpty else { return nil }

        var best: (goal: Goal, spent: Double, projected: Double, percent: Double)?

        for goal in context.goals where goal.isActive {
            let spent = spentAmount(for: goal, in: context.currentMonthExpenses)
            let projected = context.isCurrentMonth && context.elapsedMonthRatio > 0
                ? max(spent, spent / context.elapsedMonthRatio)
                : spent
            guard goal.targetAmount > 0 else { continue }

            let percent = ((projected - goal.targetAmount) / goal.targetAmount) * 100
            guard percent >= 5 || spent > goal.targetAmount else { continue }

            if best == nil || percent > (best?.percent ?? -.greatestFiniteMagnitude) {
                best = (goal, spent, projected, percent)
            }
        }

        guard let best else { return nil }

        return makeInsight(
            kind: .goalRisk,
            title: t("insight.goalRisk.title", best.goal.title),
            body: t(
                "insight.goalRisk.body",
                best.projected.asCurrency(context.currencyCode),
                best.goal.targetAmount.asCurrency(context.currencyCode)
            ),
            icon: "target",
            color: .red,
            sentiment: .alert,
            topicKey: "goal:\(best.goal.id.uuidString)",
            amount: best.projected,
            percentage: best.percent,
            category: best.goal.category?.displayName,
            merchant: nil,
            impactAmount: max(0, best.projected - best.goal.targetAmount),
            deviationPercent: best.percent,
            urgency: 95,
            basePriority: 170,
            currencyCode: context.currencyCode,
            chatPrompt: t(
                "insight.goalRisk.prompt",
                best.goal.title,
                best.projected.asCurrency(context.currencyCode),
                best.goal.targetAmount.asCurrency(context.currencyCode)
            )
        )
    }

    private static func cashFlowProjectionInsight(_ context: InsightContext) -> Insight? {
        guard context.isCurrentMonth else { return nil }

        let currentBalance = context.currentBalance
        let pending = context.remainingPendingExpenses
        let projectedVariable = max(0, context.projectedEndOfMonthTotal - context.currentMonthPaid - context.remainingCurrentMonthPending)
        let projectedBalance = currentBalance - pending - projectedVariable
        let startingPoint = max(abs(currentBalance), 1)
        let percent = ((projectedBalance - currentBalance) / startingPoint) * 100

        guard projectedBalance < 0 || projectedBalance < currentBalance * 0.2 else { return nil }

        return makeInsight(
            kind: .cashFlowProjection,
            title: projectedBalance < 0 ? t("insight.cashFlowProjection.negative.title") : t("insight.cashFlowProjection.tight.title"),
            body: t("insight.cashFlowProjection.body", projectedBalance.asCurrency(context.currencyCode)),
            icon: "wallet.bifold.fill",
            color: projectedBalance < 0 ? .red : .orange,
            sentiment: .alert,
            topicKey: "cash-flow",
            amount: projectedBalance,
            percentage: percent,
            category: nil,
            merchant: nil,
            impactAmount: abs(projectedBalance),
            deviationPercent: abs(percent),
            urgency: 70,
            basePriority: 115,
            currencyCode: context.currencyCode,
            chatPrompt: t(
                "insight.cashFlowProjection.prompt",
                projectedBalance.asCurrency(context.currencyCode)
            )
        )
    }

    private static func billDueSoonInsight(_ context: InsightContext) -> Insight? {
        let upcoming = context.scopedTransactions.filter {
            $0.type == .expense &&
            !$0.isPaid &&
            ($0.recurrenceType == .monthly || $0.recurrenceType == .installment) &&
            $0.date >= context.today &&
            $0.date <= context.calendar.date(byAdding: .day, value: 5, to: context.today) ?? context.today
        }
        .sorted { $0.date < $1.date }

        guard !upcoming.isEmpty else { return nil }

        let total = upcoming.reduce(0) { $0 + $1.amount }
        let names = upcoming.prefix(2).map { $0.placeName ?? $0.category?.displayName ?? t("insight.fallback.recurringBill") }
        let preview = names.joined(separator: ", ")

        return makeInsight(
            kind: .billDueSoon,
            title: t("insight.billDueSoon.title"),
            body: t("insight.billDueSoon.body", upcoming.count, total.asCurrency(context.currencyCode)),
            icon: "calendar.badge.exclamationmark",
            color: .orange,
            sentiment: .alert,
            topicKey: "bills-due-soon",
            amount: total,
            percentage: nil,
            category: nil,
            merchant: preview,
            impactAmount: total,
            deviationPercent: nil,
            urgency: 88,
            basePriority: 60,
            currencyCode: context.currencyCode,
            chatPrompt: t(
                "insight.billDueSoon.prompt",
                preview,
                total.asCurrency(context.currencyCode)
            )
        )
    }

    private static func spendingConcentrationInsight(_ context: InsightContext) -> Insight? {
        let daily = Dictionary(grouping: context.currentMonthPaidExpenses, by: { context.calendar.startOfDay(for: $0.date) })
            .mapValues { $0.reduce(0) { $0 + $1.amount } }

        guard daily.count >= 3, context.currentMonthPaid > 0 else { return nil }

        let sortedDays = daily.keys.sorted()
        var bestAmount = 0.0
        var bestDays: [Date] = []

        for index in sortedDays.indices {
            let window = Array(sortedDays[index..<min(index + 3, sortedDays.count)])
            let total = window.reduce(0) { $0 + (daily[$1] ?? 0) }
            if total > bestAmount {
                bestAmount = total
                bestDays = window
            }
        }

        let percent = (bestAmount / context.currentMonthPaid) * 100
        guard percent >= 45 else { return nil }

        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.effective.locale
        formatter.dateFormat = "d MMM"
        let peakDays = bestDays.map { formatter.string(from: $0) }.joined(separator: ", ")

        return makeInsight(
            kind: .spendingConcentration,
            title: t("insight.spendingConcentration.title"),
            body: t("insight.spendingConcentration.body", Int(percent.rounded()), peakDays),
            icon: "calendar.badge.clock",
            color: .orange,
            sentiment: .alert,
            topicKey: "spending-concentration",
            amount: bestAmount,
            percentage: percent,
            category: nil,
            merchant: peakDays,
            impactAmount: bestAmount,
            deviationPercent: percent,
            urgency: 58,
            basePriority: 75,
            currencyCode: context.currencyCode,
            chatPrompt: t("insight.spendingConcentration.prompt", peakDays)
        )
    }

    private static func avgTicketIncreaseInsight(_ context: InsightContext) -> Insight? {
        let currentAverage = averageTicket(for: context.currentMonthPaidExpenses)
        let previousAverage = averageTicket(for: context.previousPaidExpenses)

        guard currentAverage > 0, previousAverage > 0 else { return nil }

        let percent = ((currentAverage - previousAverage) / previousAverage) * 100
        guard percent >= 15 else { return nil }

        return makeInsight(
            kind: .avgTicketIncrease,
            title: t("insight.avgTicketIncrease.title"),
            body: t("insight.avgTicketIncrease.body", Int(percent.rounded())),
            icon: "creditcard.and.123",
            color: .orange,
            sentiment: .alert,
            topicKey: "avg-ticket",
            amount: currentAverage,
            percentage: percent,
            category: nil,
            merchant: nil,
            impactAmount: currentAverage - previousAverage,
            deviationPercent: percent,
            urgency: 55,
            basePriority: 65,
            currencyCode: context.currencyCode,
            chatPrompt: t(
                "insight.avgTicketIncrease.prompt",
                previousAverage.asCurrency(context.currencyCode),
                currentAverage.asCurrency(context.currencyCode)
            )
        )
    }

    private static func streakSavingInsight(_ context: InsightContext) -> Insight? {
        let current = context.currentMonthPaid
        let prev1 = context.monthPaid(offset: -1)
        let prev2 = context.monthPaid(offset: -2)

        guard current > 0, prev1 > 0, prev2 > 0 else { return nil }
        guard current < prev1, prev1 < prev2 else { return nil }

        let percent = ((prev2 - current) / prev2) * 100
        guard percent >= 8 else { return nil }

        return makeInsight(
            kind: .streakSaving,
            title: t("insight.streakSaving.title"),
            body: t("insight.streakSaving.body", Int(percent.rounded())),
            icon: "leaf.fill",
            color: .green,
            sentiment: .opportunity,
            topicKey: "saving-streak",
            amount: current,
            percentage: percent,
            category: nil,
            merchant: nil,
            impactAmount: prev2 - current,
            deviationPercent: percent,
            urgency: 25,
            basePriority: 40,
            currencyCode: context.currencyCode,
            chatPrompt: t("insight.streakSaving.prompt")
        )
    }

    private static func behaviorPatternInsight(_ context: InsightContext) -> Insight? {
        let sample = context.recentPaidExpenses
        guard sample.count >= 8 else { return nil }

        let weekdayTotals = Dictionary(grouping: sample, by: {
            context.calendar.component(.weekday, from: $0.date)
        }).mapValues { $0.reduce(0) { $0 + $1.amount } }

        guard let peak = weekdayTotals.max(by: { $0.value < $1.value }) else { return nil }
        let total = weekdayTotals.values.reduce(0, +)
        guard total > 0 else { return nil }

        let percent = (peak.value / total) * 100
        guard percent >= 35 else { return nil }

        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.effective.locale
        let weekdayName = formatter.weekdaySymbols[(peak.key - 1 + 7) % 7].capitalized

        return makeInsight(
            kind: .behaviorPattern,
            title: t("insight.behaviorPattern.title", weekdayName),
            body: t("insight.behaviorPattern.body", Int(percent.rounded())),
            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            color: .blue,
            sentiment: .neutral,
            topicKey: "behavior-pattern:\(peak.key)",
            amount: peak.value,
            percentage: percent,
            category: nil,
            merchant: nil,
            impactAmount: peak.value,
            deviationPercent: percent,
            urgency: 20,
            basePriority: 30,
            currencyCode: context.currencyCode,
            chatPrompt: t("insight.behaviorPattern.prompt", weekdayName)
        )
    }

    private static func categoryOverBaselineInsight(_ context: InsightContext) -> Insight? {
        var best: (categoryKey: String, categoryName: String, current: Double, percent: Double)?

        for category in context.distinctCategories {
            let current = categoryTotal(category.key, in: context.currentMonthPaidExpenses)
            let baselineMonths = (-3 ... -1).map { offset in
                categoryTotal(category.key, in: context.monthExpenses(offset: offset).filter(\.isPaid))
            }.filter { $0 > 0 }

            guard !baselineMonths.isEmpty else { continue }

            let baseline = baselineMonths.reduce(0, +) / Double(baselineMonths.count)
            guard baseline > 0 else { continue }

            let percent = ((current - baseline) / baseline) * 100
            guard percent >= 25 else { continue }

            if best == nil || percent > (best?.percent ?? 0) {
                best = (category.key, category.name, current, percent)
            }
        }

        guard let best else { return nil }

        return makeInsight(
            kind: .categoryOverBaseline,
            title: t("insight.categoryOverBaseline.title", best.categoryName),
            body: t("insight.categoryOverBaseline.body", Int(best.percent.rounded())),
            icon: "chart.bar.xaxis",
            color: .orange,
            sentiment: .alert,
            topicKey: "category-baseline:\(best.categoryKey)",
            amount: best.current,
            percentage: best.percent,
            category: best.categoryName,
            merchant: nil,
            impactAmount: best.current,
            deviationPercent: best.percent,
            urgency: 50,
            basePriority: 100,
            currencyCode: context.currencyCode,
            chatPrompt: t(
                "insight.categoryOverBaseline.prompt",
                best.categoryName,
                Int(best.percent.rounded())
            )
        )
    }

    private static func topCategoryInsight(_ context: InsightContext) -> Insight? {
        var totals: [String: Double] = [:]
        var labels: [String: String] = [:]
        var icons: [String: String] = [:]

        for tx in context.currentMonthPaidExpenses {
            guard let category = categoryIdentity(for: tx) else { continue }
            totals[category.key, default: 0] += tx.amount
            labels[category.key] = category.name
            icons[category.key] = tx.category?.rootCategory.icon ?? tx.category?.icon ?? "tag.fill"
        }

        guard let top = totals.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
        let topName = labels[top.key] ?? t("insight.fallback.uncategorized")

        let percent = context.currentMonthPaid > 0 ? (top.value / context.currentMonthPaid) * 100 : 0

        return makeInsight(
            kind: .topCategory,
            title: t("insight.topCategory.title", topName),
            body: t("insight.topCategory.body", Int(percent.rounded())),
            icon: icons[top.key] ?? "tag.fill",
            color: .blue,
            sentiment: .neutral,
            topicKey: "top-category:\(top.key)",
            amount: top.value,
            percentage: percent,
            category: topName,
            merchant: nil,
            impactAmount: top.value,
            deviationPercent: percent,
            urgency: 35,
            basePriority: 70,
            currencyCode: context.currencyCode,
            chatPrompt: t(
                "insight.topCategory.prompt",
                topName,
                top.value.asCurrency(context.currencyCode)
            )
        )
    }

    private static func installmentsInsight(_ context: InsightContext) -> Insight? {
        let installmentTransactions = context.scopedTransactions.filter {
            $0.type == .expense && $0.recurrenceType == .installment
        }

        var seenGroups = Set<UUID>()
        var totalFuture = 0.0
        var remaining = 0

        for tx in installmentTransactions {
            guard let groupId = tx.installmentGroupId, !seenGroups.contains(groupId) else { continue }
            seenGroups.insert(groupId)

            let future = installmentTransactions.filter {
                $0.installmentGroupId == groupId && $0.date > context.now && !$0.isPaid
            }
            totalFuture += future.reduce(0) { $0 + $1.amount }
            remaining += future.count
        }

        guard !seenGroups.isEmpty, totalFuture > 0 else { return nil }

        let groupCount = seenGroups.count

        return makeInsight(
            kind: .installments,
            title: t(groupCount > 1 ? "insight.installments.titlePlural" : "insight.installments.titleSingular", groupCount),
            body: t("insight.installments.body", remaining, totalFuture.asCurrency(context.currencyCode)),
            icon: "square.stack.fill",
            color: .purple,
            sentiment: .neutral,
            topicKey: "installments",
            amount: totalFuture,
            percentage: nil,
            category: nil,
            merchant: nil,
            impactAmount: totalFuture,
            deviationPercent: nil,
            urgency: 30,
            basePriority: 50,
            currencyCode: context.currencyCode,
            chatPrompt: t(
                "insight.installments.prompt",
                groupCount,
                remaining,
                totalFuture.asCurrency(context.currencyCode)
            )
        )
    }

    // MARK: - Scoring

    private static func makeInsight(
        kind: InsightType,
        title: String,
        body: String,
        icon: String,
        color: Color,
        sentiment: InsightSentiment,
        topicKey: String,
        amount: Double?,
        percentage: Double?,
        category: String?,
        merchant: String?,
        impactAmount: Double,
        deviationPercent: Double?,
        urgency: Double,
        basePriority: Double,
        currencyCode: String,
        chatPrompt: String
    ) -> Insight {
        let impactScore = min(55, log10(max(impactAmount, 1) + 1) * 18)
        let deviationScore = min(45, abs(deviationPercent ?? 0) * 0.35)
        let urgencyScore = min(35, urgency)
        let sessionPenalty = recentSessionPenalty(for: kind, topicKey: topicKey)
        let score = basePriority + impactScore + deviationScore + urgencyScore - sessionPenalty

        return Insight(
            kind: kind,
            icon: icon,
            color: color,
            title: title,
            body: body,
            chatPrompt: chatPrompt,
            score: score,
            sentiment: sentiment,
            topicKey: topicKey,
            metadata: InsightMetadata(
                amount: amount,
                percentage: percentage,
                category: category,
                merchant: merchant
            )
        )
    }

    private static func recentSessionPenalty(for kind: InsightType, topicKey: String) -> Double {
        let now = Date()
        let kindPenalty = now.timeIntervalSince(sessionHistory["kind:\(String(describing: kind))"] ?? .distantPast) < sessionRepeatWindow ? 18.0 : 0
        let topicPenalty = now.timeIntervalSince(sessionHistory["topic:\(topicKey)"] ?? .distantPast) < sessionRepeatWindow ? 30.0 : 0
        return kindPenalty + topicPenalty
    }

    // MARK: - Helpers

    private static func categoryTotal(_ categoryKey: String, in transactions: [Transaction]) -> Double {
        transactions.reduce(0) { partialResult, tx in
            partialResult + ((categoryIdentity(for: tx)?.key == categoryKey) ? tx.amount : 0)
        }
    }

    private static func averageTicket(for transactions: [Transaction]) -> Double {
        guard !transactions.isEmpty else { return 0 }
        return transactions.reduce(0) { $0 + $1.amount } / Double(transactions.count)
    }

    private static func merchantKey(_ transaction: Transaction) -> String {
        let merchant = transaction.placeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let merchant, !merchant.isEmpty {
            return merchant.lowercased()
        }
        return (transaction.category?.displayName ?? t("insight.fallback.uncategorized")).lowercased()
    }

    fileprivate static func categoryIdentity(for transaction: Transaction) -> (key: String, name: String)? {
        if let root = transaction.category?.rootCategory {
            return (root.systemKey ?? root.name, root.displayName)
        }
        if let category = transaction.category {
            return (category.systemKey ?? category.name, category.displayName)
        }
        return nil
    }

    private static func spentAmount(for goal: Goal, in transactions: [Transaction]) -> Double {
        if let category = goal.category {
            return transactions
                .filter {
                    let root = $0.category?.parent ?? $0.category
                    return root?.persistentModelID == category.persistentModelID
                        || $0.category?.persistentModelID == category.persistentModelID
                }
                .reduce(0) { $0 + $1.amount }
        }

        return transactions.reduce(0) { $0 + $1.amount }
    }
}

// MARK: - Context

private struct InsightContext {
    let calendar: Calendar
    let now: Date
    let today: Date
    let currencyCode: String
    let selectedAccountId: UUID?
    let scopedTransactions: [Transaction]
    let accounts: [Account]
    let goals: [Goal]
    let month: Int
    let year: Int

    init(
        transactions: [Transaction],
        accounts: [Account],
        goals: [Goal],
        month: Int,
        year: Int,
        currencyCode: String,
        selectedAccountId: UUID?
    ) {
        self.calendar = .current
        self.now = Date()
        self.today = Calendar.current.startOfDay(for: Date())
        self.currencyCode = currencyCode
        self.selectedAccountId = selectedAccountId
        self.accounts = accounts
        self.goals = goals
        self.month = month
        self.year = year

        if let selectedAccountId {
            self.scopedTransactions = transactions.filter { $0.account?.id == selectedAccountId }
        } else {
            self.scopedTransactions = transactions
        }
    }

    var isCurrentMonth: Bool {
        let comps = calendar.dateComponents([.month, .year], from: now)
        return comps.month == month && comps.year == year
    }

    var currentMonthExpenses: [Transaction] {
        monthExpenses(offset: 0)
    }

    var currentMonthPaidExpenses: [Transaction] {
        currentMonthExpenses.filter(\.isPaid)
    }

    var currentMonthPaid: Double {
        currentMonthPaidExpenses.reduce(0) { $0 + $1.amount }
    }

    var currentMonthPending: [Transaction] {
        currentMonthExpenses.filter { !$0.isPaid }
    }

    var remainingCurrentMonthPending: Double {
        currentMonthPending
            .filter { $0.date >= today }
            .reduce(0) { $0 + $1.amount }
    }

    var remainingPendingExpenses: Double {
        currentMonthPending
            .filter { $0.date >= today }
            .reduce(0) { $0 + $1.amount }
    }

    var previousMonthPaid: Double {
        monthPaid(offset: -1)
    }

    var previousPaidExpenses: [Transaction] {
        monthExpenses(offset: -1).filter(\.isPaid)
    }

    var recentPaidExpenses: [Transaction] {
        scopedTransactions.filter {
            $0.type == .expense &&
            $0.isPaid &&
            $0.date >= calendar.date(byAdding: .month, value: -2, to: now) ?? .distantPast &&
            $0.date <= now
        }
    }

    var pastExpenses: [Transaction] {
        scopedTransactions.filter {
            $0.type == .expense && $0.date <= now
        }
    }

    var projectedEndOfMonthTotal: Double {
        guard isCurrentMonth, elapsedMonthRatio > 0 else { return currentMonthPaid + remainingCurrentMonthPending }
        let rawProjection = currentMonthPaid / elapsedMonthRatio
        return max(rawProjection, currentMonthPaid + remainingCurrentMonthPending)
    }

    var elapsedMonthRatio: Double {
        guard isCurrentMonth else { return 1 }
        let day = Double(calendar.component(.day, from: now))
        let totalDays = Double(calendar.range(of: .day, in: .month, for: now)?.count ?? 30)
        guard totalDays > 0 else { return 1 }
        return min(max(day / totalDays, 0.01), 1)
    }

    var currentBalance: Double {
        if let selectedAccountId, let account = accounts.first(where: { $0.id == selectedAccountId }) {
            return account.balance
        }
        return accounts.reduce(0) { $0 + $1.balance }
    }

    var distinctCategories: [(key: String, name: String)] {
        var seen = Set<String>()
        var categories: [(key: String, name: String)] = []

        for transaction in scopedTransactions {
            guard let identity = InsightEngine.categoryIdentity(for: transaction) else { continue }
            guard seen.insert(identity.key).inserted else { continue }
            categories.append(identity)
        }

        return categories.sorted { $0.name < $1.name }
    }

    func monthPaid(offset: Int) -> Double {
        monthExpenses(offset: offset)
            .filter(\.isPaid)
            .reduce(0) { $0 + $1.amount }
    }

    func monthExpenses(offset: Int) -> [Transaction] {
        guard let targetDate = calendar.date(byAdding: .month, value: offset, to: referenceMonthDate) else {
            return []
        }
        let comps = calendar.dateComponents([.month, .year], from: targetDate)
        return scopedTransactions.filter {
            let txComps = calendar.dateComponents([.month, .year], from: $0.date)
            return txComps.month == comps.month && txComps.year == comps.year && $0.type == .expense
        }
    }

    private var referenceMonthDate: Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        return calendar.date(from: comps) ?? now
    }
}

private extension Array {
    mutating func appendIfPresent(_ element: Element?) {
        guard let element else { return }
        append(element)
    }
}
