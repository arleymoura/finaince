import SwiftUI
import Charts

struct CategoryDrilldownView: View {
    let category: Category
    let transactions: [Transaction]

    @Environment(\.dismiss) private var dismiss

    var categoryTransactions: [Transaction] {
        transactions.filter {
            $0.type == .expense &&
            ($0.category?.id == category.id || $0.category?.parent?.id == category.id)
        }
        .sorted { $0.date > $1.date }
    }

    var totalAmount: Double {
        categoryTransactions.reduce(0) { $0 + $1.amount }
    }

    // Agrupa por subcategoria
    var bySubcategory: [(name: String, total: Double)] {
        var dict: [String: Double] = [:]
        for t in categoryTransactions {
            let key = t.subcategory?.name ?? t.category?.name ?? "Outros"
            dict[key, default: 0] += t.amount
        }
        return dict.map { ($0.key, $0.value) }.sorted { $0.total > $1.total }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: category.icon)
                            .foregroundStyle(Color(hex: category.color))
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(category.name).font(.headline)
                            Text(totalAmount.formatted(.currency(code: "BRL")))
                                .font(.title2.bold())
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !bySubcategory.isEmpty {
                    Section("Por Subcategoria") {
                        ForEach(bySubcategory, id: \.name) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(item.total.formatted(.currency(code: "BRL")))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Transações") {
                    ForEach(categoryTransactions) { transaction in
                        TransactionRowView(transaction: transaction)
                    }
                }
            }
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}
