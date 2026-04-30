import Foundation

struct MonthReference: Hashable, Codable, Identifiable, Comparable {
    let year: Int
    let month: Int

    var id: String { "\(year)-\(String(format: "%02d", month))" }

    var isoKey: String { id }

    func title(locale: Locale = LanguageManager.shared.effective.locale) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(.dateTime.month(.wide).year().locale(locale)).capitalized
    }

    static func < (lhs: MonthReference, rhs: MonthReference) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.month < rhs.month
    }
}

enum MonthComparisonTrend: String, Codable {
    case increase
    case decrease
    case stable
}

struct MonthComparisonSummary: Codable {
    let totalA: Double
    let totalB: Double
    let goalTotalA: Double
    let goalTotalB: Double
    let difference: Double
    let percentageChange: Double
}

struct MonthComparisonCategory: Codable, Identifiable {
    let id: String
    let name: String
    let totalA: Double
    let totalB: Double
    let goalA: Double?
    let goalB: Double?
    let difference: Double
    let percentageChange: Double
    let trend: MonthComparisonTrend
}

struct MonthComparisonHighlightItem: Codable, Identifiable {
    let id: String
    let name: String
    let totalA: Double
    let totalB: Double
    let difference: Double
    let percentageChange: Double
}

struct MonthComparisonHighlights: Codable {
    let biggestIncrease: [MonthComparisonHighlightItem]
    let biggestDecrease: [MonthComparisonHighlightItem]
    let newCategories: [MonthComparisonHighlightItem]
    let removedCategories: [MonthComparisonHighlightItem]
    let anomalies: [MonthComparisonHighlightItem]
    let consistentCategories: [MonthComparisonHighlightItem]
}

struct MonthPeakDay: Codable {
    let date: Date?
    let total: Double
    let label: String
}

struct MonthSpendingDistribution: Codable {
    let early: Double
    let mid: Double
    let late: Double

    var dominantSegment: String {
        let pairs = [
            ("early", early),
            ("mid", mid),
            ("late", late)
        ]
        return pairs.max(by: { $0.1 < $1.1 })?.0 ?? "mid"
    }
}

struct MonthComparisonBehavior: Codable {
    let avgDailyA: Double
    let avgDailyB: Double
    let peakDayA: MonthPeakDay
    let peakDayB: MonthPeakDay
    let distributionA: MonthSpendingDistribution
    let distributionB: MonthSpendingDistribution
}

struct MonthComparisonResult: Codable {
    let monthA: MonthReference
    let monthB: MonthReference
    let summary: MonthComparisonSummary
    let categories: [MonthComparisonCategory]
    let highlights: MonthComparisonHighlights
    let behavior: MonthComparisonBehavior
}

struct MonthComparisonExportTransaction: Codable, Identifiable {
    let id: UUID
    let date: Date
    let amount: Double
    let merchant: String
    let category: String
    let account: String
    let notes: String
    let recurrenceType: String
    let isPaid: Bool
}

enum MonthComparatorEngine {
    static func compare(
        transactions: [Transaction],
        goals: [Goal] = [],
        monthA: MonthReference,
        monthB: MonthReference,
        selectedAccountId: UUID? = nil,
        calendar: Calendar = .current
    ) -> MonthComparisonResult {
        let expensesA = monthTransactions(
            for: monthA,
            transactions: transactions,
            selectedAccountId: selectedAccountId,
            calendar: calendar
        )
        let expensesB = monthTransactions(
            for: monthB,
            transactions: transactions,
            selectedAccountId: selectedAccountId,
            calendar: calendar
        )

        let actualTotalA = expensesA.reduce(0) { $0 + $1.amount }
        let actualTotalB = expensesB.reduce(0) { $0 + $1.amount }
        let goalTotalA = totalGoalAmount(from: goals)
        let goalTotalB = totalGoalAmount(from: goals)
        let isFutureMonthA = isFutureMonth(monthA, calendar: calendar)
        let isFutureMonthB = isFutureMonth(monthB, calendar: calendar)

        let rawCategoryTotalsA = groupedCategoryTotals(from: expensesA)
        let rawCategoryTotalsB = groupedCategoryTotals(from: expensesB)
        let categoryGoals = groupedCategoryGoals(from: goals)
        let categoryNames = Set(rawCategoryTotalsA.keys)
            .union(rawCategoryTotalsB.keys)
            .union(categoryGoals.keys)

        let categories = categoryNames
            .map { name -> MonthComparisonCategory in
                let actualA = rawCategoryTotalsA[name] ?? 0
                let actualB = rawCategoryTotalsB[name] ?? 0
                let goal = categoryGoals[name] ?? 0
                let totalA = comparableAmount(actual: actualA, goal: goal, useGoalForecast: isFutureMonthA)
                let totalB = comparableAmount(actual: actualB, goal: goal, useGoalForecast: isFutureMonthB)
                let difference = totalB - totalA
                let percentageChange = percentageChange(base: totalA, comparison: totalB)
                return MonthComparisonCategory(
                    id: name,
                    name: name,
                    totalA: totalA,
                    totalB: totalB,
                    goalA: goal > 0 ? goal : nil,
                    goalB: goal > 0 ? goal : nil,
                    difference: difference,
                    percentageChange: percentageChange,
                    trend: trend(for: difference, percentageChange: percentageChange, totalA: totalA, totalB: totalB)
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.difference) == abs(rhs.difference) {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return abs(lhs.difference) > abs(rhs.difference)
            }

        let highlights = MonthComparisonHighlights(
            biggestIncrease: categories
                .filter { $0.difference > 0.009 }
                .prefix(3)
                .map(makeHighlightItem),
            biggestDecrease: categories
                .filter { $0.difference < -0.009 }
                .sorted { abs($0.difference) > abs($1.difference) }
                .prefix(3)
                .map(makeHighlightItem),
            newCategories: categories
                .filter { $0.totalA <= 0.009 && $0.totalB > 0.009 }
                .prefix(3)
                .map(makeHighlightItem),
            removedCategories: categories
                .filter { $0.totalA > 0.009 && $0.totalB <= 0.009 }
                .prefix(3)
                .map(makeHighlightItem),
            anomalies: categories
                .filter { $0.totalA > 0.009 && $0.percentageChange > 30 }
                .prefix(3)
                .map(makeHighlightItem),
            consistentCategories: categories
                .filter { $0.totalA > 0.009 && $0.totalB > 0.009 && abs($0.percentageChange) < 5 }
                .prefix(3)
                .map(makeHighlightItem)
        )

        let totalA = categories.reduce(0) { $0 + $1.totalA }
        let totalB = categories.reduce(0) { $0 + $1.totalB }
        let comparableGoalTotalA = comparableAmount(actual: actualTotalA, goal: goalTotalA, useGoalForecast: isFutureMonthA)
        let comparableGoalTotalB = comparableAmount(actual: actualTotalB, goal: goalTotalB, useGoalForecast: isFutureMonthB)
        let difference = totalB - totalA

        let behavior = MonthComparisonBehavior(
            avgDailyA: averageDailySpending(total: actualTotalA, month: monthA, calendar: calendar),
            avgDailyB: averageDailySpending(total: actualTotalB, month: monthB, calendar: calendar),
            peakDayA: peakDay(for: expensesA, month: monthA, calendar: calendar),
            peakDayB: peakDay(for: expensesB, month: monthB, calendar: calendar),
            distributionA: spendingDistribution(for: expensesA, calendar: calendar),
            distributionB: spendingDistribution(for: expensesB, calendar: calendar)
        )

        return MonthComparisonResult(
            monthA: monthA,
            monthB: monthB,
            summary: MonthComparisonSummary(
                totalA: totalA,
                totalB: totalB,
                goalTotalA: comparableGoalTotalA,
                goalTotalB: comparableGoalTotalB,
                difference: difference,
                percentageChange: percentageChange(base: totalA, comparison: totalB)
            ),
            categories: categories,
            highlights: highlights,
            behavior: behavior
        )
    }

    static func exportTransactions(
        transactions: [Transaction],
        month: MonthReference,
        selectedAccountId: UUID? = nil,
        calendar: Calendar = .current
    ) -> [MonthComparisonExportTransaction] {
        monthTransactions(
            for: month,
            transactions: transactions,
            selectedAccountId: selectedAccountId,
            calendar: calendar
        )
        .sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.amount > rhs.amount }
            return lhs.date < rhs.date
        }
        .map { transaction in
            MonthComparisonExportTransaction(
                id: transaction.id,
                date: transaction.date,
                amount: transaction.amount,
                merchant: transaction.placeName ?? "-",
                category: categoryName(for: transaction),
                account: transaction.account?.name ?? "-",
                notes: transaction.notes ?? "",
                recurrenceType: transaction.recurrenceType.rawValue,
                isPaid: transaction.isPaid
            )
        }
    }

    private static func monthTransactions(
        for month: MonthReference,
        transactions: [Transaction],
        selectedAccountId: UUID?,
        calendar: Calendar
    ) -> [Transaction] {
        transactions.filter { transaction in
            guard transaction.type == .expense else { return false }
            let components = calendar.dateComponents([.year, .month], from: transaction.date)
            guard components.year == month.year, components.month == month.month else { return false }
            if let selectedAccountId {
                return transaction.account?.id == selectedAccountId
            }
            return true
        }
    }

    private static func groupedCategoryTotals(from transactions: [Transaction]) -> [String: Double] {
        transactions.reduce(into: [:]) { partialResult, transaction in
            partialResult[categoryName(for: transaction), default: 0] += transaction.amount
        }
    }

    private static func groupedCategoryGoals(from goals: [Goal]) -> [String: Double] {
        goals
            .filter(\.isActive)
            .reduce(into: [:]) { partialResult, goal in
                guard let category = goal.category?.rootCategory ?? goal.category else { return }
                partialResult[category.displayName, default: 0] += goal.targetAmount
            }
    }

    private static func totalGoalAmount(from goals: [Goal]) -> Double {
        goals
            .filter(\.isActive)
            .reduce(0) { $0 + $1.targetAmount }
    }

    private static func comparableAmount(actual: Double, goal: Double, useGoalForecast: Bool) -> Double {
        guard useGoalForecast else { return actual }
        return max(actual, goal)
    }

    private static func isFutureMonth(_ month: MonthReference, calendar: Calendar) -> Bool {
        let nowComponents = calendar.dateComponents([.year, .month], from: Date())
        guard let year = nowComponents.year, let currentMonth = nowComponents.month else {
            return false
        }
        return month > MonthReference(year: year, month: currentMonth)
    }

    private static func categoryName(for transaction: Transaction) -> String {
        if let category = transaction.category?.rootCategory ?? transaction.category {
            return category.displayName
        }
        return t("insight.fallback.uncategorized")
    }

    private static func percentageChange(base: Double, comparison: Double) -> Double {
        guard base > 0.009 else {
            if comparison > 0.009 { return 100 }
            return 0
        }
        return ((comparison - base) / base) * 100
    }

    private static func trend(
        for difference: Double,
        percentageChange: Double,
        totalA: Double,
        totalB: Double
    ) -> MonthComparisonTrend {
        if totalA > 0.009 && totalB > 0.009 && abs(percentageChange) < 5 {
            return .stable
        }
        if abs(difference) < 0.009 { return .stable }
        return difference > 0 ? .increase : .decrease
    }

    private nonisolated static func makeHighlightItem(from category: MonthComparisonCategory) -> MonthComparisonHighlightItem {
        MonthComparisonHighlightItem(
            id: category.id,
            name: category.name,
            totalA: category.totalA,
            totalB: category.totalB,
            difference: category.difference,
            percentageChange: category.percentageChange
        )
    }

    private static func averageDailySpending(total: Double, month: MonthReference, calendar: Calendar) -> Double {
        var components = DateComponents()
        components.year = month.year
        components.month = month.month
        components.day = 1
        let date = calendar.date(from: components) ?? Date()
        let dayCount = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        return dayCount > 0 ? total / Double(dayCount) : total
    }

    private static func peakDay(
        for transactions: [Transaction],
        month: MonthReference,
        calendar: Calendar
    ) -> MonthPeakDay {
        let totalsByDay = Dictionary(grouping: transactions) {
            calendar.startOfDay(for: $0.date)
        }
        .mapValues { values in
            values.reduce(0) { $0 + $1.amount }
        }

        guard let peak = totalsByDay.max(by: { $0.value < $1.value }) else {
            return MonthPeakDay(
                date: nil,
                total: 0,
                label: month.title(locale: LanguageManager.shared.effective.locale)
            )
        }

        let label = peak.key.formatted(
            .dateTime
                .day()
                .month(.wide)
                .locale(LanguageManager.shared.effective.locale)
        )

        return MonthPeakDay(date: peak.key, total: peak.value, label: label.capitalized)
    }

    private static func spendingDistribution(
        for transactions: [Transaction],
        calendar: Calendar
    ) -> MonthSpendingDistribution {
        transactions.reduce(
            into: MonthSpendingDistribution(early: 0, mid: 0, late: 0)
        ) { partialResult, transaction in
            let day = calendar.component(.day, from: transaction.date)
            switch day {
            case 1...10:
                partialResult = MonthSpendingDistribution(
                    early: partialResult.early + transaction.amount,
                    mid: partialResult.mid,
                    late: partialResult.late
                )
            case 11...20:
                partialResult = MonthSpendingDistribution(
                    early: partialResult.early,
                    mid: partialResult.mid + transaction.amount,
                    late: partialResult.late
                )
            default:
                partialResult = MonthSpendingDistribution(
                    early: partialResult.early,
                    mid: partialResult.mid,
                    late: partialResult.late + transaction.amount
                )
            }
        }
    }
}
