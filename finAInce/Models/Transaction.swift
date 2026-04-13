import Foundation
import SwiftData

enum TransactionType: String, Codable, CaseIterable {
    case income   = "income"
    case expense  = "expense"
    case transfer = "transfer"

    var label: String {
        switch self {
        case .income:   return "Receita"
        case .expense:  return "Despesa"
        case .transfer: return "Transferência"
        }
    }

    var icon: String {
        switch self {
        case .income:   return "arrow.down.circle.fill"
        case .expense:  return "arrow.up.circle.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .income:   return "#34C759"
        case .expense:  return "#FF3B30"
        case .transfer: return "#007AFF"
        }
    }
}

enum RecurrenceType: String, Codable, CaseIterable {
    case none        = "none"
    case monthly     = "monthly"
    case installment = "installment"

    var label: String {
        switch self {
        case .none:        return "Nenhuma"
        case .monthly:     return "Mensal"
        case .installment: return "Parcelada"
        }
    }
}

@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var type: TransactionType
    var amount: Double
    var date: Date
    var placeName: String?
    var placeGoogleId: String?
    var notes: String?
    var recurrenceType: RecurrenceType
    var installmentIndex: Int?
    var installmentTotal: Int?
    var installmentGroupId: UUID?
    var createdAt: Date

    var family: Family?
    var account: Account?
    var category: Category?
    var subcategory: Category?
    var destinationAccount: Account?

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
        installmentGroupId: UUID? = nil
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
        self.createdAt = Date()
    }
}

// MARK: - Installment helper
extension Transaction {
    /// Gera as transações futuras para um parcelamento.
    /// Deve ser chamado no momento da criação da primeira parcela.
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
                installmentGroupId: groupId
            )
            installment.family = base.family
            installment.account = base.account
            installment.category = base.category
            installment.subcategory = base.subcategory
            modelContext.insert(installment)
        }
    }
}
