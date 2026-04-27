import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable {
    case checking = "checking"
    case creditCard = "credit_card"

    var label: String {
        switch self {
        case .checking:    return t("account.type.checking")
        case .creditCard:  return t("account.type.creditCard")
        }
    }

    var defaultIcon: String {
        switch self {
        case .checking:   return "building.columns.fill"
        case .creditCard: return "creditcard.fill"
        }
    }
}

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var type: AccountType = AccountType.checking
    var balance: Double = 0
    var icon: String = ""
    var color: String = ""
    var isDefault: Bool = false
    var ccBillingStartDay: Int?
    var ccBillingEndDay: Int?
    var createdAt: Date = Date()

    var family: Family?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction]?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.destinationAccount)
    var outgoingTransfers: [Transaction]?

    init(
        name: String,
        type: AccountType,
        balance: Double = 0,
        icon: String,
        color: String,
        isDefault: Bool = false,
        ccBillingStartDay: Int? = nil,
        ccBillingEndDay: Int? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.balance = balance
        self.icon = icon
        self.color = color
        self.isDefault = isDefault
        self.ccBillingStartDay = ccBillingStartDay
        self.ccBillingEndDay = ccBillingEndDay
        self.createdAt = Date()
    }
}
