import Foundation
import SwiftData

enum GoalPeriod: String, Codable, CaseIterable {
    case monthly = "monthly"

    var label: String { "Mensal" }
}

@Model
final class Goal {
    var id: UUID = UUID()
    var title: String = ""
    var targetAmount: Double = 0
    var period: GoalPeriod = GoalPeriod.monthly
    var isActive: Bool = true
    var emoji: String = "🎯"
    var createdAt: Date = Date()

    // nil = meta geral (todos os gastos)
    var category: Category?
    var family: Family?

    init(
        title: String,
        targetAmount: Double,
        period: GoalPeriod = .monthly,
        emoji: String = "🎯",
        category: Category? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.targetAmount = targetAmount
        self.period = period
        self.isActive = true
        self.emoji = emoji
        self.category = category
        self.createdAt = Date()
    }
}

extension Goal {
    var iconName: String {
        switch emoji {
        case "🎯": return "target"
        case "💰": return "banknote.fill"
        case "🏠": return "house.fill"
        case "🍔", "🍽": return "fork.knife"
        case "🛒": return "cart.fill"
        case "🚗": return "car.fill"
        case "❤️": return "heart.fill"
        case "📚": return "book.fill"
        case "✈️": return "airplane"
        case "🎮": return "gamecontroller.fill"
        case "👕": return "tshirt.fill"
        case "💪": return "figure.strengthtraining.traditional"
        case "🐾": return "pawprint.fill"
        default: return emoji.isEmpty ? "target" : emoji
        }
    }
}
