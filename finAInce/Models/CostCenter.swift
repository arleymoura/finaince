import Foundation
import SwiftData
import SwiftUI

// MARK: - CostCenter (Project / Centro de Custo)

@Model
final class CostCenter {
    var id: UUID = UUID()
    var name: String = ""
    var desc: String?
    var icon: String = "folder.fill"
    var color: String = "#007AFF"
    var isActive: Bool = true
    var startDate: Date?
    var endDate: Date?
    var budget: Double?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        name: String,
        desc: String? = nil,
        icon: String = "folder.fill",
        color: String = "#007AFF",
        isActive: Bool = true,
        startDate: Date? = nil,
        endDate: Date? = nil,
        budget: Double? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.desc = desc
        self.icon = icon
        self.color = color
        self.isActive = isActive
        self.startDate = startDate
        self.endDate = endDate
        self.budget = budget
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Budget logic

extension CostCenter {
    enum BudgetStatus {
        case noBudget
        case normal    // < 80%
        case warning   // 80–100%
        case critical  // > 100%

        var color: Color {
            switch self {
            case .noBudget: return .accentColor
            case .normal:   return .green
            case .warning:  return .orange
            case .critical: return .red
            }
        }

        var icon: String {
            switch self {
            case .noBudget: return "minus.circle"
            case .normal:   return "checkmark.circle.fill"
            case .warning:  return "exclamationmark.triangle.fill"
            case .critical: return "xmark.octagon.fill"
            }
        }
    }

    func budgetStatus(spent: Double) -> BudgetStatus {
        guard let budget, budget > 0 else { return .noBudget }
        let ratio = spent / budget
        if ratio > 1.0  { return .critical }
        if ratio >= 0.8 { return .warning }
        return .normal
    }

    func budgetProgress(spent: Double) -> Double {
        guard let budget, budget > 0 else { return 0 }
        return min(spent / budget, 1.0)
    }
}

// MARK: - Preset icon / color options

extension CostCenter {
    static let iconOptions: [String] = [
        "folder.fill", "suitcase.fill", "house.fill", "car.fill",
        "fork.knife", "airplane", "heart.fill", "star.fill",
        "briefcase.fill", "cart.fill", "gift.fill", "graduationcap.fill",
        "music.note", "camera.fill", "paintbrush.fill", "wrench.and.screwdriver.fill",
        "laptopcomputer", "tv.fill", "dumbbell.fill", "pawprint.fill"
    ]

    static let colorOptions: [String] = [
        "#007AFF", "#34C759", "#FF9500", "#FF3B30",
        "#AF52DE", "#5AC8FA", "#FF2D55", "#FFCC00",
        "#00C7BE", "#30D158", "#FFD60A", "#FF6961"
    ]
}
