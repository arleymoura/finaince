import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var selectedMonth = Calendar.current.component(.month, from: Date())
    @State private var selectedYear  = Calendar.current.component(.year,  from: Date())
    @State private var showNewTransaction = false
    @State private var showReceiptScanner = false

    var filteredTransactions: [Transaction] {
        transactions.filter {
            let c = Calendar.current.dateComponents([.month, .year], from: $0.date)
            return c.month == selectedMonth && c.year == selectedYear
        }
    }

    // Agrupa por dia
    var groupedByDay: [(date: Date, transactions: [Transaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTransactions) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
                      .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredTransactions.isEmpty {
                    emptyState
                } else {
                    transactionList
                }
            }
            .navigationTitle("Extrato")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showNewTransaction) {
                NewTransactionFlowView()
            }
            .sheet(isPresented: $showReceiptScanner) {
                // ReceiptScannerView() — Sprint 4
                Text("Scanner de Recibo — em breve")
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Subviews

    private var transactionList: some View {
        List {
            MonthSelectorView(month: $selectedMonth, year: $selectedYear)
                .listRowBackground(Color.clear)
                .listRowInsets(.init())

            ForEach(groupedByDay, id: \.date) { group in
                Section(header: Text(group.date.formatted(.dateTime.day().month(.wide).locale(.init(identifier: "pt_BR"))).capitalized)) {
                    ForEach(group.transactions) { transaction in
                        TransactionRowView(transaction: transaction)
                    }
                    .onDelete { indexSet in
                        deleteTransactions(group.transactions, at: indexSet)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            MonthSelectorView(month: $selectedMonth, year: $selectedYear)
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Nenhuma transação neste mês")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Adicionar Transação") {
                showNewTransaction = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showNewTransaction = true } label: {
                Image(systemName: "plus.circle.fill")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button { showReceiptScanner = true } label: {
                Label("Escanear Recibo", systemImage: "camera.viewfinder")
            }
        }
    }

    private func deleteTransactions(_ group: [Transaction], at indexSet: IndexSet) {
        for index in indexSet {
            modelContext.delete(group[index])
        }
    }
}

// MARK: - Transaction Row

struct TransactionRowView: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category?.icon ?? transaction.type.icon)
                .foregroundStyle(Color(hex: transaction.category?.color ?? "#8E8E93"))
                .frame(width: 32, height: 32)
                .background(Color(hex: transaction.category?.color ?? "#8E8E93").opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.placeName ?? transaction.category?.name ?? "Sem categoria")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let notes = transaction.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if transaction.recurrenceType == .installment,
                   let idx = transaction.installmentIndex,
                   let total = transaction.installmentTotal {
                    Text("Parcela \(idx) de \(total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(transaction.amount.formatted(.currency(code: "BRL")))
                .font(.subheadline.bold())
                .foregroundStyle(transaction.type == .income ? Color.green : Color.primary)
        }
        .padding(.vertical, 2)
    }
}
