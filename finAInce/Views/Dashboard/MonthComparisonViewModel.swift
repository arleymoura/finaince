import Foundation
import SwiftUI

@MainActor
@Observable
final class MonthComparisonViewModel {
    let currencyCode: String
    let selectedAccountId: UUID?
    let availableMonths: [MonthReference]

    var monthA: MonthReference
    var monthB: MonthReference
    var result: MonthComparisonResult?
    var aiInsight: String = ""
    var isLoadingAIInsight = false
    var isPreparingExport = false
    var exportURL: URL?
    var exportErrorMessage: String?

    private let transactions: [Transaction]
    private let aiSettings: AISettings?

    init(
        transactions: [Transaction],
        currencyCode: String,
        aiSettings: AISettings?,
        selectedAccountId: UUID? = nil,
        initialMonthA: MonthReference? = nil,
        initialMonthB: MonthReference? = nil
    ) {
        self.transactions = transactions
        self.currencyCode = currencyCode
        self.aiSettings = aiSettings
        self.selectedAccountId = selectedAccountId

        let months = Self.makeAvailableMonths(from: transactions)
        self.availableMonths = months

        let defaults = Self.defaultMonths(from: months, initialMonthA: initialMonthA, initialMonthB: initialMonthB)
        self.monthA = defaults.0
        self.monthB = defaults.1
    }

    func load() async {
        refreshLocalResult()
        await loadAIInsight()
        prepareExport()
    }

    func monthChanged() async {
        guard monthA != monthB else { return }
        refreshLocalResult()
        await loadAIInsight()
        prepareExport()
    }

    var canCompare: Bool {
        monthA != monthB
    }

    var summaryTrendColor: Color {
        guard let result else { return .secondary }
        if result.summary.difference > 0 { return .red }
        if result.summary.difference < 0 { return .green }
        return .secondary
    }

    var fallbackInsight: String {
        guard let result else { return t("monthComparator.ai.empty") }
        let percentage = Int(result.summary.percentageChange.rounded())
        if result.summary.difference > 0, let first = result.highlights.biggestIncrease.first {
            return t("monthComparator.ai.moreSpent", "\(percentage)", first.name)
        }
        if result.summary.difference < 0, let first = result.highlights.biggestDecrease.first {
            return t("monthComparator.ai.saved", "\(abs(percentage))", first.name)
        }
        return t("monthComparator.ai.stable")
    }

    private func refreshLocalResult() {
        result = MonthComparatorEngine.compare(
            transactions: transactions,
            monthA: monthA,
            monthB: monthB,
            selectedAccountId: selectedAccountId
        )
        aiInsight = fallbackInsight
        exportErrorMessage = nil
    }

    private func loadAIInsight() async {
        guard let result, let aiSettings, aiSettings.isConfigured else { return }
        isLoadingAIInsight = true
        do {
            aiInsight = try await AIService.generateMonthComparisonInsight(
                result: result,
                currencyCode: currencyCode,
                settings: aiSettings
            )
        } catch {
            aiInsight = fallbackInsight
        }
        isLoadingAIInsight = false
    }

    private func prepareExport() {
        guard let result else { return }
        isPreparingExport = true
        defer { isPreparingExport = false }

        do {
            let monthATransactions = MonthComparatorEngine.exportTransactions(
                transactions: transactions,
                month: result.monthA,
                selectedAccountId: selectedAccountId
            )
            let monthBTransactions = MonthComparatorEngine.exportTransactions(
                transactions: transactions,
                month: result.monthB,
                selectedAccountId: selectedAccountId
            )
            exportURL = try MonthComparisonExporter.writeComparisonFile(
                result: result,
                transactionsMonthA: monthATransactions,
                transactionsMonthB: monthBTransactions,
                currencyCode: currencyCode
            )
        } catch {
            exportURL = nil
            exportErrorMessage = error.localizedDescription
        }
    }

    private static func makeAvailableMonths(from transactions: [Transaction]) -> [MonthReference] {
        let calendar = Calendar.current
        let transactionMonths = transactions
            .filter { $0.type == .expense }
            .map {
                MonthReference(
                    year: calendar.component(.year, from: $0.date),
                    month: calendar.component(.month, from: $0.date)
                )
            }

        let now = Date()
        let current = MonthReference(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now)
        )
        let previousDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let previous = MonthReference(
            year: calendar.component(.year, from: previousDate),
            month: calendar.component(.month, from: previousDate)
        )

        return Array(Set(transactionMonths + [current, previous])).sorted(by: >)
    }

    private static func defaultMonths(
        from availableMonths: [MonthReference],
        initialMonthA: MonthReference?,
        initialMonthB: MonthReference?
    ) -> (MonthReference, MonthReference) {
        if let initialMonthA, let initialMonthB {
            return (initialMonthA, initialMonthB)
        }

        let calendar = Calendar.current
        let now = Date()
        let current = MonthReference(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now)
        )
        let previousDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let previous = MonthReference(
            year: calendar.component(.year, from: previousDate),
            month: calendar.component(.month, from: previousDate)
        )

        let monthB = availableMonths.first(where: { $0 == current }) ?? availableMonths.first ?? current
        let monthA = availableMonths.first(where: { $0 == previous }) ?? availableMonths.dropFirst().first ?? previous
        return (monthA, monthB)
    }
}
