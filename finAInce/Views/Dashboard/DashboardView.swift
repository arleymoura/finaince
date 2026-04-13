import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [Transaction]

    @State private var selectedMonth = Calendar.current.component(.month, from: Date())
    @State private var selectedYear  = Calendar.current.component(.year,  from: Date())
    @State private var drilldownCategory: Category?

    var filteredTransactions: [Transaction] {
        transactions.filter {
            let c = Calendar.current.dateComponents([.month, .year], from: $0.date)
            return c.month == selectedMonth && c.year == selectedYear
        }
    }

    var totalIncome: Double {
        filteredTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    var totalExpense: Double {
        filteredTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    var balance: Double { totalIncome - totalExpense }

    // Agrupa despesas por categoria raiz
    var expensesByCategory: [(category: Category, total: Double)] {
        let expenses = filteredTransactions.filter { $0.type == .expense }
        var dict: [Category: Double] = [:]
        for t in expenses {
            guard let cat = t.category else { continue }
            let root = cat.parent ?? cat
            dict[root, default: 0] += t.amount
        }
        return dict.map { ($0.key, $0.value) }
                   .sorted { $0.total > $1.total }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthSelectorView(month: $selectedMonth, year: $selectedYear)
                    balanceSummary
                    categoryChart
                    categoryList
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .sheet(item: $drilldownCategory) { category in
                CategoryDrilldownView(category: category,
                                      transactions: filteredTransactions)
            }
        }
    }

    // MARK: - Subviews

    private var balanceSummary: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SummaryCard(title: "Receitas", amount: totalIncome,  color: .green)
                SummaryCard(title: "Despesas", amount: totalExpense, color: .red)
            }
            HStack {
                Text("Saldo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(balance.formatted(.currency(code: "BRL")))
                    .font(.title2.bold())
                    .foregroundStyle(balance >= 0 ? Color.green : Color.red)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gastos por Categoria")
                .font(.headline)

            if expensesByCategory.isEmpty {
                Text("Nenhum gasto registrado")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(expensesByCategory, id: \.category.id) { item in
                    SectorMark(
                        angle: .value("Valor", item.total),
                        innerRadius: .ratio(0.55)
                    )
                    .foregroundStyle(Color(hex: item.category.color))
                    .annotation(position: .overlay) {
                        Text(item.category.name)
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Detalhamento")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(expensesByCategory, id: \.category.id) { item in
                CategoryRowView(category: item.category,
                                amount: item.total,
                                total: totalExpense)
                .onTapGesture { drilldownCategory = item.category }
                Divider()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Supporting Views

struct SummaryCard: View {
    let title: String
    let amount: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(amount.formatted(.currency(code: "BRL")))
                .font(.headline)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CategoryRowView: View {
    let category: Category
    let amount: Double
    let total: Double

    var percentage: Double { total > 0 ? amount / total : 0 }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .foregroundStyle(Color(hex: category.color))
                .frame(width: 24)

            Text(category.name)
                .font(.subheadline)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(amount.formatted(.currency(code: "BRL")))
                    .font(.subheadline.bold())
                Text("\(Int(percentage * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct MonthSelectorView: View {
    @Binding var month: Int
    @Binding var year: Int

    var title: String {
        var comps = DateComponents()
        comps.month = month; comps.year = year; comps.day = 1
        let date = Calendar.current.date(from: comps) ?? Date()
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "pt_BR")
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date).capitalized
    }

    var body: some View {
        HStack {
            Button { move(by: -1) } label: {
                Image(systemName: "chevron.left").font(.headline)
            }
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
            Button { move(by: 1) } label: {
                Image(systemName: "chevron.right").font(.headline)
            }
        }
        .padding(.horizontal)
    }

    private func move(by delta: Int) {
        var comps = DateComponents()
        comps.month = month + delta; comps.year = year
        if let date = Calendar.current.date(from: comps) {
            let c = Calendar.current.dateComponents([.month, .year], from: date)
            month = c.month!; year = c.year!
        }
    }
}
