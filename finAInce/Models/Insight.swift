import SwiftUI

// MARK: - Insight Kind

enum InsightType: Hashable {
    case priceChange
    case spendingPace
    case topCategory
    case monthComparison
    case installments
    case subscriptionUnused
    case endOfMonthProjection
    case abnormalTransaction
    case categoryTrendUp
    case goalRisk
    case cashFlowProjection
    case billDueSoon
    case spendingConcentration
    case avgTicketIncrease
    case streakSaving
    case behaviorPattern
    case categoryOverBaseline
    case bestPurchaseTiming
    case closingRisk
    case attentionWindow
    case creditCardSpendingTrend
    case creditLimitRisk
    case creditCardForecastOverflow
}

typealias InsightKind = InsightType

enum InsightSentiment {
    case alert
    case opportunity
    case neutral
}

struct InsightMetadata {
    let amount: Double?
    let percentage: Double?
    let category: String?
    let merchant: String?
}

// MARK: - Insight

struct Insight: Identifiable {
    let id = UUID()
    let kind: InsightType
    let icon: String
    let color: Color
    let title: String
    let body: String
    /// Pre-formatted prompt to send to the LLM when the user taps "Saiba mais".
    let chatPrompt: String
    let score: Double
    let sentiment: InsightSentiment
    let topicKey: String
    let metadata: InsightMetadata?
}

struct DailyInsight: Identifiable {
    let id = UUID()
    let sourceInsight: Insight
    let title: String
    let explanation: String
    let action: String
    let chatPrompt: String

    var icon: String { sourceInsight.icon }
    var color: Color { sourceInsight.color }
    var sentiment: InsightSentiment { sourceInsight.sentiment }
}

// MARK: - IdentifiableString (shared helper)

/// Thin Identifiable wrapper so a plain String can drive `.sheet(item:)`.
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}
