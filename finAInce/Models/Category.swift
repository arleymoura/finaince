import Foundation
import SwiftData

enum CategoryType: String, Codable, CaseIterable {
    case expense = "expense"
    case both    = "both"

    var label: String {
        switch self {
        case .expense: return t("transaction.type.expense")
        case .both:    return t("transaction.general")
        }
    }
}

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var systemKey: String?
    var icon: String = ""
    var color: String = ""
    var type: CategoryType = CategoryType.expense
    var isSystem: Bool = false
    var sortOrder: Int = 0

    var family: Family?

    // Self-referential — nil = categoria raiz, non-nil = subcategoria
    var parent: Category?

    @Relationship(deleteRule: .cascade, inverse: \Category.parent)
    var subcategories: [Category]?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.subcategory)
    var subcategoryTransactions: [Transaction]?

    @Relationship(deleteRule: .nullify, inverse: \Goal.category)
    var goals: [Goal]?

    init(
        name: String,
        systemKey: String? = nil,
        icon: String,
        color: String,
        type: CategoryType,
        isSystem: Bool = false,
        sortOrder: Int = 0,
        parent: Category? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.systemKey = systemKey
        self.icon = icon
        self.color = color
        self.type = type
        self.isSystem = isSystem
        self.sortOrder = sortOrder
        self.parent = parent
    }

    var displayName: String {
        DefaultCategories.localizedName(for: systemKey, fallback: name)
    }

    var rootCategory: Category {
        parent ?? self
    }

    var rootSystemKey: String? {
        rootCategory.systemKey
    }
}
