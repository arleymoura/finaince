import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable {
    case checking = "checking"
    case cash = "cash"
    case creditCard = "credit_card"

    var label: String {
        switch self {
        case .checking:    return t("account.type.checking")
        case .cash:        return t("account.type.cash")
        case .creditCard:  return t("account.type.creditCard")
        }
    }

    var defaultIcon: String {
        switch self {
        case .checking:   return "building.columns.fill"
        case .cash:       return "wallet.bifold.fill"
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
    var ccPaymentDueDay: Int?
    var ccCreditLimit: Double?
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
        ccBillingEndDay: Int? = nil,
        ccPaymentDueDay: Int? = nil,
        ccCreditLimit: Double? = nil
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
        self.ccPaymentDueDay = ccPaymentDueDay
        self.ccCreditLimit = ccCreditLimit
        self.createdAt = Date()
    }
}

extension Account {
    var billingClosingDay: Int? {
        ccBillingEndDay
    }

    var billingStartDay: Int? {
        guard let closingDay = ccBillingEndDay else { return nil }
        return closingDay
    }

    var billingCycleEndDay: Int? {
        guard let closingDay = ccBillingEndDay else { return nil }
        return closingDay == 1 ? 31 : closingDay - 1
    }

    func billingCycleRange(containing referenceDate: Date, calendar: Calendar = .current) -> (start: Date, end: Date, nextStart: Date)? {
        guard let closingDay = ccBillingEndDay else { return nil }

        func clippedDate(year: Int, month: Int, day: Int) -> Date? {
            guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let maxDay = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count else {
                return nil
            }
            return calendar.date(from: DateComponents(year: year, month: month, day: min(day, maxDay)))
        }

        let referenceStart = calendar.startOfDay(for: referenceDate)
        let referenceComponents = calendar.dateComponents([.year, .month], from: referenceStart)

        guard let thisMonthClosing = clippedDate(
            year: referenceComponents.year ?? calendar.component(.year, from: referenceStart),
            month: referenceComponents.month ?? calendar.component(.month, from: referenceStart),
            day: closingDay
        ) else { return nil }

        let cycleStart: Date
        if referenceStart >= calendar.startOfDay(for: thisMonthClosing) {
            cycleStart = calendar.startOfDay(for: thisMonthClosing)
        } else {
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: referenceStart) ?? referenceStart
            let previousComponents = calendar.dateComponents([.year, .month], from: previousMonth)
            guard let previousClosing = clippedDate(
                year: previousComponents.year ?? calendar.component(.year, from: previousMonth),
                month: previousComponents.month ?? calendar.component(.month, from: previousMonth),
                day: closingDay
            ) else { return nil }
            cycleStart = calendar.startOfDay(for: previousClosing)
        }

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: cycleStart) ?? cycleStart
        let nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
        guard let nextCycleStartRaw = clippedDate(
            year: nextComponents.year ?? calendar.component(.year, from: nextMonth),
            month: nextComponents.month ?? calendar.component(.month, from: nextMonth),
            day: closingDay
        ) else { return nil }

        let nextCycleStart = calendar.startOfDay(for: nextCycleStartRaw)
        let displayEnd = calendar.date(byAdding: .day, value: -1, to: nextCycleStart) ?? nextCycleStart
        return (start: cycleStart, end: displayEnd, nextStart: nextCycleStart)
    }
}
