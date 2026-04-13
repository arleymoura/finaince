import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]

    @State private var showAddAccount = false
    @State private var accountToEdit: Account?

    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty {
                    emptyState
                } else {
                    accountList
                }
            }
            .navigationTitle("Contas")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddAccount = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showAddAccount) {
                AccountFormView()
            }
            .sheet(item: $accountToEdit) { account in
                AccountFormView(account: account)
            }
        }
    }

    // MARK: - Subviews

    private var accountList: some View {
        List {
            ForEach(accounts.sorted { $0.isDefault && !$1.isDefault }) { account in
                AccountRowView(account: account) {
                    setDefault(account)
                }
                .onTapGesture { accountToEdit = account }
            }
            .onDelete(perform: deleteAccounts)
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Nenhuma conta cadastrada")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Adicionar Conta") { showAddAccount = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func setDefault(_ account: Account) {
        accounts.forEach { $0.isDefault = false }
        account.isDefault = true
    }

    private func deleteAccounts(at indexSet: IndexSet) {
        let sorted = accounts.sorted { $0.isDefault && !$1.isDefault }
        for index in indexSet {
            modelContext.delete(sorted[index])
        }
    }
}

// MARK: - Account Row

struct AccountRowView: View {
    let account: Account
    let onSetDefault: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: account.icon)
                .font(.title2)
                .foregroundStyle(Color(hex: account.color))
                .frame(width: 48, height: 48)
                .background(Color(hex: account.color).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(account.name)
                        .font(.headline)
                    if account.isDefault {
                        Text("Padrão")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text(account.type.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if account.type == .creditCard,
                   let start = account.ccBillingStartDay,
                   let end = account.ccBillingEndDay {
                    Text("Fatura: dia \(start) ao dia \(end)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(account.balance.formatted(.currency(code: "BRL")))
                    .font(.subheadline.bold())
                    .foregroundStyle(account.balance >= 0 ? Color.primary : Color.red)

                if !account.isDefault {
                    Button("Tornar padrão", action: onSetDefault)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Account Form

struct AccountFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var account: Account?

    @State private var name = ""
    @State private var type: AccountType = .checking
    @State private var icon = "building.columns.fill"
    @State private var color = "#007AFF"
    @State private var ccStartDay = 6
    @State private var ccEndDay = 5

    let availableColors = ["#007AFF", "#34C759", "#FF9500", "#FF3B30", "#AF52DE", "#FF2D55", "#5AC8FA", "#FFCC00"]

    var isEditing: Bool { account != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Informações") {
                    TextField("Nome da conta", text: $name)
                    Picker("Tipo", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                }

                if type == .creditCard {
                    Section("Janela da Fatura") {
                        Stepper("Início: dia \(ccStartDay)", value: $ccStartDay, in: 1...28)
                        Stepper("Fim: dia \(ccEndDay)",      value: $ccEndDay,   in: 1...28)
                    }
                }

                Section("Cor") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                        ForEach(availableColors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().stroke(Color.primary.opacity(color == hex ? 1 : 0), lineWidth: 2)
                                )
                                .onTapGesture { color = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isEditing ? "Editar Conta" : "Nova Conta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .disabled(name.isEmpty)
                }
            }
        }
        .onAppear { populateIfEditing() }
    }

    private func populateIfEditing() {
        guard let account else { return }
        name = account.name
        type = account.type
        icon = account.icon
        color = account.color
        ccStartDay = account.ccBillingStartDay ?? 6
        ccEndDay = account.ccBillingEndDay ?? 5
    }

    private func save() {
        if let account {
            account.name = name
            account.type = type
            account.icon = type.defaultIcon
            account.color = color
            account.ccBillingStartDay = type == .creditCard ? ccStartDay : nil
            account.ccBillingEndDay   = type == .creditCard ? ccEndDay   : nil
        } else {
            let newAccount = Account(
                name: name,
                type: type,
                icon: type.defaultIcon,
                color: color,
                ccBillingStartDay: type == .creditCard ? ccStartDay : nil,
                ccBillingEndDay:   type == .creditCard ? ccEndDay   : nil
            )
            modelContext.insert(newAccount)
        }
        dismiss()
    }
}
