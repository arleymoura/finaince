import Foundation
import SwiftData

struct SampleData {

    static func seed(in modelContext: ModelContext) {

        // MARK: - Contas

        let checking = Account(
            name: "Nubank Conta",
            type: .checking,
            balance: 4_500.00,
            icon: "building.columns.fill",
            color: "#8B5CF6",
            isDefault: true
        )
        let wallet = Account(
            name: t("account.walletDefault"),
            type: .cash,
            balance: 320.00,
            icon: "wallet.bifold.fill",
            color: "#34C759",
            isDefault: false
        )
        let creditCard = Account(
            name: "Nubank Cartão",
            type: .creditCard,
            balance: 0,
            icon: "creditcard.fill",
            color: "#8B5CF6",
            isDefault: false,
            ccBillingStartDay: 1,
            ccBillingEndDay: 10,
            ccCreditLimit: 5_000
        )
        modelContext.insert(checking)
        modelContext.insert(wallet)
        modelContext.insert(creditCard)

        // MARK: - Busca categorias

        let allCategories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []

        func cat(_ systemKey: String) -> Category? {
            DefaultCategories.category(withSystemKey: systemKey, in: allCategories)
        }

        func sub(_ systemKey: String, of parentSystemKey: String) -> Category? {
            DefaultCategories.subcategory(
                withSystemKey: systemKey,
                parentSystemKey: parentSystemKey,
                in: allCategories
            )
        }

        // MARK: - Datas do mês corrente

        let cal = Calendar.current
        let now = Date()
        let year  = cal.component(.year,  from: now)
        let month = cal.component(.month, from: now)

        func date(_ day: Int) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day)) ?? now
        }

        // MARK: - Definições de transações

        typealias TxDef = (
            type: TransactionType,
            amount: Double,
            date: Date,
            place: String,
            account: Account,
            category: Category?,
            subcategory: Category?,
            isPaid: Bool
        )

        let today = cal.component(.day, from: now)

        let definitions: [TxDef] = [

            // Moradia — aluguel e condomínio como pendentes (vence depois do dia atual)
            (.expense, 1_800.00, date(5),  "Aluguel",        checking,   cat("housing"),     sub("housing.rent",        of: "housing"),     date(5)  <= now),
            (.expense,   180.00, date(20), "Condomínio",     checking,   cat("housing"),     sub("housing.condo",       of: "housing"),     today >= 20),
            (.expense,    89.90, date(15), "Vivo Fibra",     checking,   cat("housing"),     sub("housing.internet",    of: "housing"),     today >= 15),
            (.expense,   120.00, date(25), "Energia",        checking,   cat("housing"),     sub("housing.energy",      of: "housing"),     today >= 25),

            // Supermercado
            (.expense,   320.00, date(3),  "Supermercado",   checking,   cat("groceries"), sub("groceries.market", of: "groceries"), true),
            (.expense,   165.00, date(11), "Supermercado",   checking,   cat("groceries"), sub("groceries.market", of: "groceries"), date(11) <= now),

            // Restaurantes
            (.expense,    75.50, date(6),  "iFood",          creditCard, cat("restaurants"), sub("restaurants.delivery", of: "restaurants"), true),
            (.expense,    45.00, date(9),  "Restaurante",    creditCard, cat("restaurants"), sub("restaurants.lunchDinner", of: "restaurants"), date(9) <= now),

            // Transporte
            (.expense,   250.00, date(4),  "Combustível",    checking,   cat("transport"),  sub("transport.fuel", of: "transport"),  true),
            (.expense,    32.00, date(8),  "Uber",           creditCard, cat("transport"),  sub("transport.rideHailing", of: "transport"),  true),

            // Saúde — plano pendente, farmácia paga
            (.expense,   380.00, date(10), "Plano de Saúde", checking,   cat("health"),       sub("health.insurance", of: "health"),       today >= 10),
            (.expense,    65.00, date(6),  "Farmácia",       creditCard, cat("health"),       sub("health.pharmacy",  of: "health"),       true),

            // Lazer
            (.expense,    49.90, date(1),  "Netflix",        creditCard, cat("subscriptions"), sub("subscriptions.streaming", of: "subscriptions"), true),
            (.expense,   120.00, date(12), "Barzinho",       creditCard, cat("restaurants"),  sub("restaurants.bars", of: "restaurants"), date(12) <= now),
        ]

        for def in definitions {
            let tx = Transaction(
                type: def.type,
                amount: def.amount,
                date: def.date,
                placeName: def.place,
                isPaid: def.isPaid
            )
            tx.account     = def.account
            tx.category    = def.category
            tx.subcategory = def.subcategory
            modelContext.insert(tx)
        }
    }
}
