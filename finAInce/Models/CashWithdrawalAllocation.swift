import Foundation
import SwiftData

@Model
final class CashWithdrawalAllocation {
    var id: UUID = UUID()
    var allocatedAmount: Double = 0
    var createdAt: Date = Date()

    var withdrawalTransaction: Transaction?
    var expenseTransaction: Transaction?

    init(
        allocatedAmount: Double,
        withdrawalTransaction: Transaction? = nil,
        expenseTransaction: Transaction? = nil
    ) {
        self.id = UUID()
        self.allocatedAmount = allocatedAmount
        self.createdAt = Date()
        self.withdrawalTransaction = withdrawalTransaction
        self.expenseTransaction = expenseTransaction
    }
}
