import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query private var accounts: [Account]
    
    @State private var accountToEdit: Account?
    @State private var showDeleteConfirm = false
    @State private var accountsToDelete: [Account] = []
    
    @Binding var selectedAccount: Account?
    @Binding var showCreateAccount: Bool
       
    
    
    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty {
                    emptyState
                } else {
                    accountList
                }
            }
            .navigationTitle(t("account.title"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreateAccount = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(item: $accountToEdit) { account in
                AccountFormView(account: account)
            }
            // (DeleteAccountDialog overlay removed)
        }
    }
    
    struct DeleteAccountDialog: View {
        let onConfirm: () -> Void
        let onCancel: () -> Void

        var body: some View {
            VStack(spacing: 0) {

                // HEADER
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    Text(t("account.deleteTitle"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)

                // BODY
                VStack(spacing: 10) {
                    Text(t("common.cannotUndo"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(t("account.deleteMessage"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // ACTIONS
                VStack(spacing: 10) {

                    Button {
                        onConfirm()
                    } label: {
                        Text(t("account.deleteForever"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        onCancel()
                    } label: {
                        Text(t("common.cancel"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
            .frame(maxWidth: 320)
        }
    }
    

    // MARK: - Subviews

    private var accountList: some View {
        List {
            ForEach(accounts.sorted { $0.isDefault && !$1.isDefault }) { account in
                AccountRowView(account: account)
                    .onTapGesture { accountToEdit = account }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(t("account.empty"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Button(t("account.add")) { showCreateAccount = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func deleteAccounts(at indexSet: IndexSet) {
        let sorted = accounts.sorted { $0.isDefault && !$1.isDefault }
        for index in indexSet {
            modelContext.delete(sorted[index])
        }
    }

    private func deleteAccountsConfirmed() {
        for account in accountsToDelete {
            modelContext.delete(account)
        }
        accountsToDelete = []
    }
}

struct AccountsProfileSection: View {
    @Query private var accounts: [Account]

    @Binding var selectedAccount: Account?
    @Binding var showCreateAccount: Bool

    var body: some View {
        Section {
            if accounts.isEmpty {
                Button {
                    showCreateAccount = true
                } label: {
                    Label(t("account.add"), systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                ForEach(accounts.sorted { $0.isDefault && !$1.isDefault }) { account in
                    AccountRowView(account: account)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedAccount = account }
                }

                Button {
                    showCreateAccount = true
                } label: {
                    Label(t("account.new"), systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        } header: {
            Text(t("account.title"))
        }
        .sheet(isPresented: $showCreateAccount) {
            AccountFormView()
        }
    }
}

// MARK: - Account Row

struct AccountRowView: View {
    let account: Account

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
                        Text(t("common.default"))
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
                   let closingDay = account.billingClosingDay {
                    Text(t("account.closingDay", closingDay))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if account.type == .creditCard,
                   let dueDay = account.ccPaymentDueDay {
                    Text(t("account.paymentDueDay", dueDay))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if account.type == .creditCard,
                   let creditLimit = account.ccCreditLimit {
                    Text(t("account.creditLimitValue", creditLimit.asCurrency()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Account Form

struct AccountFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    var account: Account?

    @State private var name       = ""
    @State private var type: AccountType = .checking
    @State private var icon       = "building.columns.fill"
    @State private var color      = "#007AFF"
    @State private var ccEndDay   = 5
    @State private var ccDueDay   = 12
    @State private var ccLimitText = ""
    @State private var isDefault  = false
    @State private var showDeleteConfirm = false

    let availableColors = ["#007AFF", "#34C759", "#FF9500", "#FF3B30", "#AF52DE", "#FF2D55", "#5AC8FA", "#FFCC00"]

    var isEditing: Bool { account != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section(t("account.info")) {
                    TextField(t("account.namePlaceholder"), text: $name)
                    Picker(t("account.type"), selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    Toggle(isOn: $isDefault) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("account.default"))
                            Text(t("account.defaultDesc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.accentColor)
                }

                if type == .creditCard {
                    Section(t("account.billingWindowTitle")) {
                        Stepper(t("account.closingDay", ccEndDay), value: $ccEndDay, in: 1...28)
                        Stepper(t("account.paymentDueDay", ccDueDay), value: $ccDueDay, in: 1...31)
                        HStack(spacing: 8) {
                            Text(t("account.creditLimit"))
                            Spacer()
                            Text((CurrencyOption(rawValue: currencyCode)
                                  ?? CurrencyOption(rawValue: CurrencyOption.defaultCode)
                                  ?? .usd).symbol)
                                .font(.body.bold())
                                .foregroundStyle(.secondary)
                            TextField(
                                t("account.creditLimitPlaceholder"),
                                text: $ccLimitText
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section(t("account.color")) {
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

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Text(t("account.deleteTitle"))
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? t("account.edit") : t("account.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.save")) { save() }
                        .disabled(name.isEmpty)
                }
            }
        }
        .onAppear { populateIfEditing() }
        .overlay {
            if showDeleteConfirm {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { showDeleteConfirm = false }

                    AccountsView.DeleteAccountDialog(
                        onConfirm: {
                            deleteAccount()
                            showDeleteConfirm = false
                        },
                        onCancel: {
                            showDeleteConfirm = false
                        }
                    )
                }
            }
        }
    }

    private func populateIfEditing() {
        guard let account else { return }
        name       = account.name
        type       = account.type
        icon       = account.icon
        color      = account.color
        isDefault  = account.isDefault
        ccEndDay   = account.billingClosingDay ?? 5
        ccDueDay   = account.ccPaymentDueDay ?? 12
        ccLimitText = account.ccCreditLimit.map(Self.formatAmountInput) ?? ""
    }

    private func save() {
        let creditLimit = parsedCreditLimit

        // Se esta conta vai ser padrão, desmarca todas as outras
        if isDefault {
            let all = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
            all.forEach { $0.isDefault = false }
        }

        if let account {
            account.name              = name
            account.type              = type
            account.icon              = type.defaultIcon
            account.color             = color
            account.isDefault         = isDefault
            account.ccBillingStartDay = type == .creditCard ? ccEndDay : nil
            account.ccBillingEndDay   = type == .creditCard ? ccEndDay   : nil
            account.ccPaymentDueDay   = type == .creditCard ? ccDueDay   : nil
            account.ccCreditLimit     = type == .creditCard ? creditLimit : nil
        } else {
            let newAccount = Account(
                name: name,
                type: type,
                icon: type.defaultIcon,
                color: color,
                isDefault: isDefault,
                ccBillingStartDay: type == .creditCard ? ccEndDay : nil,
                ccBillingEndDay:   type == .creditCard ? ccEndDay   : nil,
                ccPaymentDueDay:   type == .creditCard ? ccDueDay   : nil,
                ccCreditLimit:     type == .creditCard ? creditLimit : nil
            )
            modelContext.insert(newAccount)
        }
        dismiss()
    }

    private func deleteAccount() {
        guard let account else { return }
        modelContext.delete(account)
        dismiss()
    }

    private var parsedCreditLimit: Double? {
        let trimmed = ccLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current

        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }

        let fallback = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(fallback)
    }

    nonisolated private static func formatAmountInput(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
