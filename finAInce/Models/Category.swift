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
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var color: String
    var type: CategoryType
    var isSystem: Bool
    var sortOrder: Int

    var family: Family?

    // Self-referential — nil = categoria raiz, non-nil = subcategoria
    var parent: Category?

    @Relationship(deleteRule: .cascade, inverse: \Category.parent)
    var subcategories: [Category] = []

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    init(
        name: String,
        icon: String,
        color: String,
        type: CategoryType,
        isSystem: Bool = false,
        sortOrder: Int = 0,
        parent: Category? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.color = color
        self.type = type
        self.isSystem = isSystem
        self.sortOrder = sortOrder
        self.parent = parent
    }
}
