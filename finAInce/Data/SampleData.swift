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
        let creditCard = Account(
            name: "Nubank Cartão",
            type: .creditCard,
            balance: 0,
            icon: "creditcard.fill",
            color: "#8B5CF6",
            isDefault: false,
            ccBillingStartDay: 1,
            ccBillingEndDay: 10
        )
        modelContext.insert(checking)
        modelContext.insert(creditCard)

        // MARK: - Busca categorias

        let allCategories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []

        func cat(_ name: String) -> Category? {
            allCategories.first { $0.name == name && $0.parent == nil }
        }

        func sub(_ name: String, of parentName: String) -> Category? {
            guard let parentCat = cat(parentName) else { return nil }
            return allCategories.first { $0.name == name && $0.parent?.id == parentCat.id }
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
            (.expense, 1_800.00, date(5),  "Aluguel",        checking,   cat("Moradia"),     sub("Aluguel",        of: "Moradia"),     date(5)  <= now),
            (.expense,   180.00, date(20), "Condomínio",     checking,   cat("Moradia"),     sub("Condomínio",     of: "Moradia"),     today >= 20),
            (.expense,    89.90, date(15), "Vivo Fibra",     checking,   cat("Moradia"),     sub("Internet",       of: "Moradia"),     today >= 15),
            (.expense,   120.00, date(25), "Energia",        checking,   cat("Moradia"),     sub("Energia",        of: "Moradia"),     today >= 25),

            // Supermercado
            (.expense,   320.00, date(3),  "Supermercado",   checking,   cat("Supermercado"), sub("Mercado",        of: "Supermercado"), true),
            (.expense,   165.00, date(11), "Supermercado",   checking,   cat("Supermercado"), sub("Mercado",        of: "Supermercado"), date(11) <= now),

            // Restaurantes
            (.expense,    75.50, date(6),  "iFood",          creditCard, cat("Restaurantes"), sub("Delivery",       of: "Restaurantes"), true),
            (.expense,    45.00, date(9),  "Restaurante",    creditCard, cat("Restaurantes"), sub("Almoço / Jantar", of: "Restaurantes"), date(9) <= now),

            // Transporte
            (.expense,   250.00, date(4),  "Combustível",    checking,   cat("Transporte"),  sub("Combustível",    of: "Transporte"),  true),
            (.expense,    32.00, date(8),  "Uber",           creditCard, cat("Transporte"),  sub("Uber / Táxi",    of: "Transporte"),  true),

            // Saúde — plano pendente, farmácia paga
            (.expense,   380.00, date(10), "Plano de Saúde", checking,   cat("Saúde"),       sub("Plano de Saúde", of: "Saúde"),       today >= 10),
            (.expense,    65.00, date(6),  "Farmácia",       creditCard, cat("Saúde"),       sub("Farmácia",       of: "Saúde"),       true),

            // Lazer
            (.expense,    49.90, date(1),  "Netflix",        creditCard, cat("Lazer"),       sub("Assinaturas",    of: "Lazer"),       true),
            (.expense,   120.00, date(12), "Barzinho",       creditCard, cat("Lazer"),       sub("Bares",          of: "Lazer"),       date(12) <= now),
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
