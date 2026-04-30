import Foundation
import SwiftData

enum TransactionType: String, Codable, CaseIterable {
    case expense  = "expense"
    case transfer = "transfer"

    var label: String {
        switch self {
        case .expense:  return t("transaction.type.expense")
        case .transfer: return t("transaction.type.transfer")
        }
    }

    var icon: String {
        switch self {
        case .expense:  return "arrow.up.circle.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .expense:  return "#FF3B30"
        case .transfer: return "#007AFF"
        }
    }
}

enum RecurrenceType: String, Codable, CaseIterable {
    case none        = "none"
    case monthly     = "monthly"
    case annual      = "annual"
    case installment = "installment"

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? RecurrenceType.none.rawValue
        self = RecurrenceType(rawValue: rawValue) ?? .none
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var label: String {
        switch self {
        case .none:        return t("recurrence.none")
        case .monthly:     return t("recurrence.monthly")
        case .annual:      return t("recurrence.annual")
        case .installment: return t("recurrence.installment")
        }
    }
}

@Model
final class Transaction {
    var id: UUID = UUID()
    var type: TransactionType = TransactionType.expense
    var amount: Double = 0
    var date: Date = Date()
    var placeName: String?
    var placeGoogleId: String?
    var notes: String?
    var recurrenceType: RecurrenceType = RecurrenceType.none
    var installmentIndex: Int?
    var installmentTotal: Int?
    var installmentGroupId: UUID?
    var createdAt: Date = Date()
    var isPaid: Bool = true
    /// Hash used to detect re-imports of the same bank statement row.
    /// Format: "yyyy-MM-dd|description|amount" — set automatically on import.
    var importHash: String?
    /// UUID of the CostCenter (project) this transaction belongs to. Optional.
    var costCenterId: UUID?

    var family: Family?
    var account: Account?
    var category: Category?
    var subcategory: Category?
    var destinationAccount: Account?

    @Relationship(deleteRule: .cascade, inverse: \ReceiptAttachment.transaction)
    var receiptAttachments: [ReceiptAttachment]?

    init(
        type: TransactionType,
        amount: Double,
        date: Date = Date(),
        placeName: String? = nil,
        placeGoogleId: String? = nil,
        notes: String? = nil,
        recurrenceType: RecurrenceType = .none,
        installmentIndex: Int? = nil,
        installmentTotal: Int? = nil,
        installmentGroupId: UUID? = nil,
        isPaid: Bool = true
    ) {
        self.id = UUID()
        self.type = type
        self.amount = amount
        self.date = date
        self.placeName = placeName
        self.placeGoogleId = placeGoogleId
        self.notes = notes
        self.recurrenceType = recurrenceType
        self.installmentIndex = installmentIndex
        self.installmentTotal = installmentTotal
        self.installmentGroupId = installmentGroupId
        self.isPaid = isPaid
        self.createdAt = Date()
    }
}

// MARK: - Recurrence helpers
extension Transaction {

    /// Gera as transações futuras para um parcelamento.
    static func generateInstallments(
        from base: Transaction,
        total: Int,
        in modelContext: ModelContext
    ) {
        guard total > 1 else { return }
        let groupId = UUID()
        base.installmentIndex = 1
        base.installmentTotal = total
        base.installmentGroupId = groupId

        for index in 2...total {
            var comps = DateComponents()
            comps.month = index - 1
            let futureDate = Calendar.current.date(byAdding: comps, to: base.date) ?? base.date

            let installment = Transaction(
                type: base.type,
                amount: base.amount,
                date: futureDate,
                placeName: base.placeName,
                notes: base.notes,
                recurrenceType: .installment,
                installmentIndex: index,
                installmentTotal: total,
                installmentGroupId: groupId,
                isPaid: false
            )
            installment.family  = base.family
            installment.account = base.account
            installment.category    = base.category
            installment.subcategory = base.subcategory
            modelContext.insert(installment)
        }
    }

    /// Gera 60 meses de recorrência mensal a partir da transação base.
    static func generateMonthlyRecurrences(
        from base: Transaction,
        months: Int = 60,
        in modelContext: ModelContext
    ) {
        guard months > 1 else { return }
        let groupId = UUID()
        base.installmentIndex = 1
        base.installmentTotal = months
        base.installmentGroupId = groupId

        for index in 2...months {
            var comps = DateComponents()
            comps.month = index - 1
            let futureDate = Calendar.current.date(byAdding: comps, to: base.date) ?? base.date

            let recurring = Transaction(
                type: base.type,
                amount: base.amount,
                date: futureDate,
                placeName: base.placeName,
                notes: base.notes,
                recurrenceType: .monthly,
                installmentIndex: index,
                installmentTotal: months,
                installmentGroupId: groupId,
                isPaid: false
            )
            recurring.family  = base.family
            recurring.account = base.account
            recurring.category    = base.category
            recurring.subcategory = base.subcategory
            modelContext.insert(recurring)
        }
    }

    /// Gera 20 anos de recorrência anual a partir da transação base.
    static func generateAnnualRecurrences(
        from base: Transaction,
        years: Int = 20,
        in modelContext: ModelContext
    ) {
        guard years > 1 else { return }
        let groupId = UUID()
        base.installmentIndex = 1
        base.installmentTotal = years
        base.installmentGroupId = groupId

        for index in 2...years {
            var comps = DateComponents()
            comps.year = index - 1
            let futureDate = Calendar.current.date(byAdding: comps, to: base.date) ?? base.date

            let recurring = Transaction(
                type: base.type,
                amount: base.amount,
                date: futureDate,
                placeName: base.placeName,
                notes: base.notes,
                recurrenceType: .annual,
                installmentIndex: index,
                installmentTotal: years,
                installmentGroupId: groupId,
                isPaid: false
            )
            recurring.family  = base.family
            recurring.account = base.account
            recurring.category    = base.category
            recurring.subcategory = base.subcategory
            modelContext.insert(recurring)
        }
    }
}
