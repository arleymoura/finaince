import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

// MARK: - Scope de edição de recorrência

enum RecurrenceEditScope {
    case thisOnly
    case thisAndFuture
    case all
}

private struct ExistingCashExpensePickerSheet: View {
    let withdrawal: Transaction
    let currencyCode: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var selectedMonth: Date
    @State private var isSearching = false
    @State private var searchText = ""

    init(withdrawal: Transaction, currencyCode: String) {
        self.withdrawal = withdrawal
        self.currencyCode = currencyCode
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: withdrawal.date)?.start ?? withdrawal.date
        _selectedMonth = State(initialValue: monthStart)
    }

    private var sortedExpenses: [Transaction] {
        eligibleExpenses.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.amount > rhs.amount }
            return lhs.date > rhs.date
        }
    }

    private var eligibleExpenses: [Transaction] {
        allTransactions.filter { candidate in
            guard candidate.id != withdrawal.id else { return false }
            guard candidate.type == .expense else { return false }
            guard candidate.account?.type == .cash else { return false }
            guard candidate.parentCashWithdrawal == nil || candidate.parentCashWithdrawal?.id == withdrawal.id else { return false }

            guard matchesDateFilter(candidate.date) else { return false }

            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSearch.isEmpty else { return true }

            let normalizedQuery = trimmedSearch.normalizedForMatching()
            let merchant = candidate.placeName?.normalizedForMatching() ?? ""
            let category = candidate.category?.displayName.normalizedForMatching() ?? ""
            let subcategory = candidate.subcategory?.displayName.normalizedForMatching() ?? ""
            let notes = candidate.notes?.normalizedForMatching() ?? ""
            return merchant.contains(normalizedQuery)
                || category.contains(normalizedQuery)
                || subcategory.contains(normalizedQuery)
                || notes.contains(normalizedQuery)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("transaction.cashAssociationSheetInfo"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(t("transaction.cashAllocated"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(withdrawal.allocatedCashAmount.asCurrency(currencyCode))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                        }

                        HStack {
                            Text(t("transaction.cashRemaining"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(withdrawal.remainingCashAmount.asCurrency(currencyCode))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(withdrawal.remainingCashAmount > 0.009 ? .blue : .green)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    monthNavigator
                }

                if isSearching {
                    Section {
                        TextField(t("transaction.searchCashExpenses"), text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text(t("transaction.cashSearchUpToNextMonth"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(t("transaction.cashAssociationAvailable")) {
                    if sortedExpenses.isEmpty {
                        Text(t("transaction.cashAssociationNoEligible"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedExpenses) { expense in
                            associationRow(for: expense, isAssociated: expense.parentCashWithdrawal?.id == withdrawal.id)
                        }
                    }
                }
            }
            .navigationTitle(t("transaction.associateExistingCashExpense"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.close")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(t("common.search")) {
                        isSearching.toggle()
                        if !isSearching {
                            searchText = ""
                        }
                    }
                }
            }
        }
    }

    private var monthNavigator: some View {
        let locale = LanguageManager.shared.effective.locale

        return HStack(spacing: 12) {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 4) {
                Text(selectedMonth.formatted(.dateTime.month(.wide).year().locale(locale)))
                    .font(.headline)
                Text(isSearching ? t("transaction.cashSearchUpToNextMonth") : t("transaction.cashMonthFilter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(isNextMonthOrLater(selectedMonth))
        }
        .padding(.vertical, 4)
    }

    private func matchesDateFilter(_ date: Date) -> Bool {
        let calendar = Calendar.current

        if !isSearching {
            guard let interval = calendar.dateInterval(of: .month, for: selectedMonth) else { return false }
            return interval.contains(date)
        }

        guard let start = calendar.dateInterval(of: .month, for: withdrawal.date)?.start else { return false }
        guard
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: start),
            let end = calendar.dateInterval(of: .month, for: nextMonth)?.end
        else { return false }

        return date >= start && date < end
    }

    private func changeMonth(by delta: Int) {
        let calendar = Calendar.current
        guard let updated = calendar.date(byAdding: .month, value: delta, to: selectedMonth) else { return }
        selectedMonth = calendar.dateInterval(of: .month, for: updated)?.start ?? updated
    }

    private func isNextMonthOrLater(_ month: Date) -> Bool {
        let calendar = Calendar.current
        guard let currentMonthStart = calendar.dateInterval(of: .month, for: Date())?.start else { return false }
        return month >= currentMonthStart
    }

    @ViewBuilder
    private func associationRow(for expense: Transaction, isAssociated: Bool) -> some View {
        let canAssociate = isAssociated || expense.amount <= withdrawal.remainingCashAmount + 0.009

        Button {
            toggleAssociation(for: expense, isAssociated: isAssociated)
            if !isAssociated {
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isAssociated ? "checkmark.circle.fill" : (canAssociate ? "circle" : "exclamationmark.circle"))
                    .foregroundStyle(isAssociated ? .green : (canAssociate ? .secondary : .orange))

                VStack(alignment: .leading, spacing: 3) {
                    Text(expense.placeName ?? expense.category?.displayName ?? t("transaction.noPlace"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(expense.date.formatted(.dateTime.day().month(.abbreviated).year().locale(LanguageManager.shared.effective.locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(expense.amount.asCurrency(currencyCode))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(canAssociate || isAssociated ? Color.primary : Color.orange)
            }
        }
        .buttonStyle(.plain)
        .disabled(!canAssociate && !isAssociated)
    }

    private func toggleAssociation(for expense: Transaction, isAssociated: Bool) {
        if isAssociated {
            guard let allocation = (withdrawal.outgoingCashAllocations ?? []).first(where: { $0.expenseTransaction?.id == expense.id }) else { return }
            modelContext.delete(allocation)
            return
        }

        guard expense.amount <= withdrawal.remainingCashAmount + 0.009 else { return }
        let allocation = CashWithdrawalAllocation(
            allocatedAmount: expense.amount,
            withdrawalTransaction: withdrawal,
            expenseTransaction: expense
        )
        modelContext.insert(allocation)
    }
}

private struct CashExpenseWithdrawalPickerSheet: View {
    let expense: Transaction
    let withdrawals: [Transaction]
    let currencyCode: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var currentWithdrawal: Transaction? {
        expense.parentCashWithdrawal
    }

    private var sortedWithdrawals: [Transaction] {
        withdrawals.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.remainingCashAmount > rhs.remainingCashAmount }
            return lhs.date > rhs.date
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(t("transaction.cashExpenseAssociationInfo"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section(t("transaction.cashExpenseCurrentWithdrawal")) {
                    if let currentWithdrawal {
                        withdrawalRow(for: currentWithdrawal, isAssociated: true)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    removeCurrentAssociation()
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                    } else {
                        Text(t("transaction.cashExpenseNoWithdrawal"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(t("transaction.cashExpenseAvailableWithdrawals")) {
                    if sortedWithdrawals.isEmpty {
                        Text(t("transaction.cashExpenseNoEligibleWithdrawals"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedWithdrawals) { withdrawal in
                            withdrawalRow(for: withdrawal, isAssociated: currentWithdrawal?.id == withdrawal.id)
                        }
                    }
                }
            }
            .navigationTitle(t("transaction.associateToWithdrawal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.close")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func withdrawalRow(for withdrawal: Transaction, isAssociated: Bool) -> some View {
        let canAssociate = isAssociated || expense.amount <= withdrawal.remainingCashAmount + (isAssociated ? expense.allocatedFromCashWithdrawalAmount : 0) + 0.009

        Button {
            toggleAssociation(to: withdrawal, isAssociated: isAssociated)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isAssociated ? "checkmark.circle.fill" : (canAssociate ? "circle" : "exclamationmark.circle"))
                    .foregroundStyle(isAssociated ? .green : (canAssociate ? .secondary : .orange))

                VStack(alignment: .leading, spacing: 3) {
                    Text(withdrawal.placeName ?? t("transaction.cashWithdrawalDefaultName"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(withdrawal.date.formatted(.dateTime.day().month(.abbreviated).year().locale(LanguageManager.shared.effective.locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(withdrawal.amount.asCurrency(currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(t("transaction.cashRemainingValue", withdrawal.remainingCashAmount.asCurrency(currencyCode)))
                        .font(.caption)
                        .foregroundStyle(canAssociate || isAssociated ? Color.secondary : Color.orange)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canAssociate && !isAssociated)
    }

    private func toggleAssociation(to withdrawal: Transaction, isAssociated: Bool) {
        if let existingAllocation = (expense.incomingCashAllocations ?? []).first {
            modelContext.delete(existingAllocation)
            if isAssociated {
                return
            }
        }

        guard expense.amount <= withdrawal.remainingCashAmount + 0.009 else { return }
        let allocation = CashWithdrawalAllocation(
            allocatedAmount: expense.amount,
            withdrawalTransaction: withdrawal,
            expenseTransaction: expense
        )
        modelContext.insert(allocation)
    }

    private func removeCurrentAssociation() {
        guard let existingAllocation = (expense.incomingCashAllocations ?? []).first else { return }
        modelContext.delete(existingAllocation)
    }
}

// MARK: - View

private struct RecurrenceAmountPoint: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Double
    let isForecast: Bool
    let isCurrent: Bool
}

private enum RecurrenceMonthLabelStyle {
    case abbreviated
    case wide
}

struct TransactionEditView: View {
    let transaction: Transaction

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.createdAt)   private var accounts: [Account]
    @Query private var costCenters: [CostCenter]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @AppStorage("app.currencyCode")    private var currencyCode = CurrencyOption.defaultCode

    // Local state — aplicado no Save, descartado no Cancel
    @State private var amountText   = ""
    @State private var placeName    = ""
    @State private var date         = Date()
    @State private var selectedAccount: Account?  = nil
    @State private var selectedCategory: Category? = nil
    @State private var selectedSubcategory: Category? = nil
    @State private var notes  = ""
    @State private var isPaid = true
    @State private var selectedRecurrenceMonth: Date? = nil

    // Recurrence editing (only applicable when not yet in a series)
    @State private var editedRecurrenceType:  RecurrenceType = .none
    @State private var editedInstallmentTotal: Int = 2

    // Project
    @State private var selectedCostCenter: CostCenter? = nil
    @State private var showProjectPicker = false

    // Sheets & dialogs
    @State private var showCategoryPicker   = false
    @State private var showRecurrenceDialog = false
    @State private var showDeleteDialog     = false
    @State private var showReceiptCamera    = false
    @State private var showReceiptLibrary   = false
    @State private var showReceiptPDFPicker = false
    @State private var showExistingCashExpensePicker = false
    @State private var showNewCashExpenseFlow = false
    @State private var showWithdrawalPickerSheet = false
    @State private var selectedAssociatedExpense: Transaction? = nil
    @State private var previewURL: URL?     = nil

    // MARK: - Derived

    /// True when this transaction belongs to a recurring / installment series.
    private var isInRecurrenceSeries: Bool {
        transaction.installmentGroupId != nil
    }

    private var seriesLabel: String {
        let idx   = transaction.installmentIndex ?? 1
        let total = transaction.installmentTotal ?? 1
        switch transaction.recurrenceType {
        case .monthly:
            return t("transaction.monthlyRecurrenceSeries", idx, total)
        case .annual:
            return t("transaction.annualRecurrenceSeries", idx, total)
        case .installment:
            return t("transaction.installmentSeries", idx, total)
        case .none:
            return ""
        }
    }

    private var isCardBillPayment: Bool {
        transaction.kind == .cardBillPayment
    }

    private var isCashWithdrawal: Bool {
        transaction.kind == .cashWithdrawal
    }

    private var paidCreditCardAccount: Account? {
        transaction.destinationAccount
    }

    private var withdrawalDestinationAccount: Account? {
        transaction.destinationAccount
    }

    private var associatedCashExpenses: [Transaction] {
        transaction.allocatedExpenses
    }

    private var eligibleCashExpenses: [Transaction] {
        allTransactions.filter { candidate in
            guard candidate.id != transaction.id else { return false }
            guard candidate.type == .expense else { return false }
            guard candidate.account?.type == .cash else { return false }
            guard candidate.parentCashWithdrawal == nil || candidate.parentCashWithdrawal?.id == transaction.id else { return false }
            return true
        }
    }

    private var newCashExpenseInitialState: NewTransactionState {
        let state = NewTransactionState()
        state.type = .expense
        state.kind = .regular
        state.allowsKindSelection = false
        state.account = transaction.destinationAccount
        state.date = transaction.date
        state.isPaid = true
        return state
    }

    private var isCashExpense: Bool {
        !isCashWithdrawal && transaction.type == .expense && selectedAccount?.type == .cash
    }

    private var selectedCashWithdrawal: Transaction? {
        transaction.parentCashWithdrawal
    }

    private var eligibleWithdrawals: [Transaction] {
        allTransactions.filter { candidate in
            guard candidate.id != transaction.id else { return false }
            guard candidate.kind == .cashWithdrawal else { return false }
            guard candidate.parentCashWithdrawal == nil else { return false }
            guard candidate.account?.type == .checking else { return false }
            guard candidate.remainingCashAmount > 0.009 || candidate.id == selectedCashWithdrawal?.id else { return false }
            return true
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {

                // Valor
                Section(t("transaction.amount")) {
                    HStack(spacing: 8) {
                        Text((CurrencyOption(rawValue: currencyCode)
                              ?? CurrencyOption(rawValue: CurrencyOption.defaultCode)
                              ?? .usd).symbol)
                            .font(.title3.bold())
                            .foregroundStyle(.secondary)
                        TextField(t("transaction.amountPlaceholder"), text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title3.bold())
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 4)
                }
                
                //Pagamento de fatura
                if isCardBillPayment {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue.opacity(0.14))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "creditcard.and.123")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t("transaction.billPaymentCard"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(paidCreditCardAccount?.name ?? t("common.none"))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                if isCashWithdrawal {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.orange.opacity(0.14))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "banknote")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(t("transaction.cashWithdrawalAccount"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(withdrawalDestinationAccount?.name ?? t("common.none"))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }

                    Section(t("transaction.cashAllocationTitle")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                allocationMetric(
                                    title: t("transaction.cashAllocated"),
                                    value: transaction.allocatedCashAmount.asCurrency(currencyCode),
                                    color: .orange
                                )
                                Spacer()
                                allocationMetric(
                                    title: t("transaction.cashRemaining"),
                                    value: transaction.remainingCashAmount.asCurrency(currencyCode),
                                    color: transaction.remainingCashAmount > 0.009 ? .blue : .green
                                )
                            }

                            HStack(spacing: 10) {
                                Button {
                                    showExistingCashExpensePicker = true
                                } label: {
                                    compactActionBadge(
                                        title: t("transaction.associateExistingCashExpense"),
                                        systemImage: "link.badge.plus",
                                        tint: .accentColor
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showNewCashExpenseFlow = true
                                } label: {
                                    compactActionBadge(
                                        title: t("transaction.createNewCashExpense"),
                                        systemImage: "plus.circle.fill",
                                        tint: .green
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if !associatedCashExpenses.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(t("transaction.associatedExpenses"))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    ForEach(associatedCashExpenses.prefix(3)) { expense in
                                        Button {
                                            selectedAssociatedExpense = expense
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: expense.category?.icon ?? "banknote")
                                                    .foregroundStyle(Color(hex: expense.category?.color ?? "#8E8E93"))
                                                    .frame(width: 28, height: 28)
                                                    .background(Color(hex: expense.category?.color ?? "#8E8E93").opacity(0.12))
                                                    .clipShape(Circle())

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(expense.placeName ?? expense.category?.displayName ?? t("transaction.noPlace"))
                                                        .font(.subheadline)
                                                        .foregroundStyle(.primary)
                                                        .lineLimit(1)
                                                    Text(expense.date.formatted(.dateTime.day().month(.abbreviated).locale(LanguageManager.shared.effective.locale)))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }

                                                Spacer()

                                                Text(expense.amount.asCurrency(currencyCode))
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Detalhes
                Section(t("transaction.details")) {
                    HStack {
                        Label(t("transaction.place"), systemImage: "mappin.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Color.accentColor)
                        TextField(t("transaction.establishment"), text: $placeName)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker(t("transaction.date"), selection: $date, displayedComponents: .date)

                    Picker(t("transaction.account"), selection: $selectedAccount) {
                        Text(t("common.none")).tag(Account?.none)
                        ForEach(accounts) { account in
                            Label(account.name, systemImage: account.icon)
                                .tag(Account?.some(account))
                        }
                    }

                    HStack {
                        Label(
                            isPaid ? t("transaction.paid") : t("transaction.pending"),
                            systemImage: isPaid ? "checkmark.circle.fill" : "clock.fill"
                        )
                        .foregroundStyle(isPaid ? Color.green : Color.orange)
                        Spacer()
                        Toggle("", isOn: $isPaid)
                            .labelsHidden()
                            .tint(.green)
                    }
                }

                if isCashExpense {
                    Section(t("transaction.associateToWithdrawal")) {
                        Button {
                            showWithdrawalPickerSheet = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "banknote")
                                    .foregroundStyle(Color.orange)
                                    .frame(width: 32, height: 32)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedCashWithdrawal?.placeName ?? t("transaction.cashExpenseNoWithdrawal"))
                                        .foregroundStyle(.primary)
                                    if let selectedCashWithdrawal {
                                        Text(selectedCashWithdrawal.date.formatted(.dateTime.day().month(.abbreviated).year().locale(LanguageManager.shared.effective.locale)))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if selectedCashWithdrawal != nil {
                                Button(role: .destructive) {
                                    removeCashWithdrawalAssociation()
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }

                if !isCardBillPayment && !isCashWithdrawal {
                   
                    // Categoria
                    Section(t("transaction.category")) {
                        Button {
                            showCategoryPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                if let cat = selectedCategory {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(hex: cat.color).opacity(0.15))
                                            .frame(width: 32, height: 32)
                                        Image(systemName: cat.icon)
                                            .font(.subheadline)
                                            .foregroundStyle(Color(hex: cat.color))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cat.displayName)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        if let sub = selectedSubcategory {
                                            Text(sub.displayName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                } else {
                                    Image(systemName: "tag")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, height: 32)
                                    Text(t("transaction.noCategory"))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Projeto
                    if !costCenters.filter(\.isActive).isEmpty {
                        Section(t("projects.section")) {
                            Button { showProjectPicker = true } label: {
                                HStack(spacing: 12) {
                                    if let cc = selectedCostCenter {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(hex: cc.color).opacity(0.15))
                                                .frame(width: 32, height: 32)
                                            Image(systemName: cc.icon)
                                                .font(.subheadline)
                                                .foregroundStyle(Color(hex: cc.color))
                                        }
                                        Text(cc.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                    } else {
                                        Image(systemName: "folder")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 32, height: 32)
                                        Text(t("projects.noProject"))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .sheet(isPresented: $showProjectPicker) {
                                ProjectPickerSheet(selectedCostCenter: $selectedCostCenter)
                            }
                        }
                    }
                }

                // Recorrência
                Section(t("newTx.recurrence")) {
                    if isInRecurrenceSeries {
                        // Already part of a series — show read-only badge
                        HStack(spacing: 8) {
                            Image(systemName: transaction.recurrenceType == .installment
                                  ? "list.number" : "repeat")
                                .foregroundStyle(Color.accentColor)
                            Text(seriesLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        // Not in a series — allow converting
                        Picker(t("newTx.type"), selection: $editedRecurrenceType) {
                            Text(t("recurrence.none")).tag(RecurrenceType.none)
                            Text(t("recurrence.monthly")).tag(RecurrenceType.monthly)
                            Text(t("recurrence.annual")).tag(RecurrenceType.annual)
                            Text(t("recurrence.installment")).tag(RecurrenceType.installment)
                        }

                        if editedRecurrenceType == .installment {
                            Stepper(
                                t("transaction.installmentsCount", editedInstallmentTotal),
                                value: $editedInstallmentTotal,
                                in: 2...48
                            )
                        }

                        if editedRecurrenceType == .monthly {
                            Label(t("newTx.installmentsNote"),
                                  systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if editedRecurrenceType == .annual {
                            Label(t("newTx.annualNote"),
                                  systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                
                //recibos
                Section(t("receipt.attachments")) {
                    ReceiptAttachmentSourceBar(
                        onCamera: { showReceiptCamera = true },
                        onGallery: { showReceiptLibrary = true },
                        onPDF: { showReceiptPDFPicker = true }
                    )

                    if sortedReceiptAttachments.isEmpty {
                        Text(t("receipt.noAttachments"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedReceiptAttachments) { attachment in
                            ReceiptAttachmentRow(
                                name: attachment.fileName,
                                kind: attachment.kind,
                                onPreview: { previewURL = ReceiptAttachmentStore.fileURL(for: attachment) },
                                onRemove: { ReceiptAttachmentStore.remove(attachment, in: modelContext) }
                            )
                        }
                    }
                }

                // Notas
                Section(t("transaction.notes")) {
                    TextField(t("transaction.notesPlaceholder"), text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
               
                if shouldShowRecurrenceInsight {
                    Section {
                        recurrenceInsightCard
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteDialog = true
                    } label: {
                        Label(t("transaction.delete"), systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle(t("transaction.editTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.save")) {
                        if isInRecurrenceSeries {
                            showRecurrenceDialog = true
                        } else {
                            save(scope: .thisOnly)
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                t("transaction.editRecTitle"),
                isPresented: $showRecurrenceDialog,
                titleVisibility: .visible
            ) {
                Button(t("transaction.editThis")) { save(scope: .thisOnly) }
                Button(t("transaction.editThisNext")) { save(scope: .thisAndFuture) }
                Button(t("transaction.editAll")) { save(scope: .all) }
                Button(t("common.cancel"), role: .cancel) {}
            } message: {
                Text(t("transaction.editRecMsg"))
            }
            .confirmationDialog(
                isInRecurrenceSeries ? t("transaction.deleteRecTitle") : t("transaction.delete"),
                isPresented: $showDeleteDialog,
                titleVisibility: .visible
            ) {
                if isInRecurrenceSeries {
                    Button(t("transaction.deleteThis"), role: .destructive) {
                        delete(scope: .thisOnly)
                    }
                    Button(t("transaction.deleteThisNext"), role: .destructive) {
                        delete(scope: .thisAndFuture)
                    }
                    Button(t("transaction.deleteAll"), role: .destructive) {
                        delete(scope: .all)
                    }
                } else {
                    Button(t("transaction.delete"), role: .destructive) {
                        delete(scope: .thisOnly)
                    }
                }
                Button(t("common.cancel"), role: .cancel) {}
            } message: {
                Text(isInRecurrenceSeries ? t("transaction.deleteRecMsg") : t("common.cannotUndo"))
            }
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerSheet(
                    selectedCategory:    $selectedCategory,
                    selectedSubcategory: $selectedSubcategory,
                    transactionType:     transaction.type
                )
            }
            .sheet(isPresented: $showExistingCashExpensePicker) {
                ExistingCashExpensePickerSheet(
                    withdrawal: transaction,
                    currencyCode: currencyCode
                )
            }
            .sheet(isPresented: $showNewCashExpenseFlow) {
                NewTransactionFlowView(
                    initialState: newCashExpenseInitialState,
                    jumpToReview: false
                ) { expense in
                    associateNewCashExpense(expense)
                }
            }
            .sheet(isPresented: $showWithdrawalPickerSheet) {
                CashExpenseWithdrawalPickerSheet(
                    expense: transaction,
                    withdrawals: eligibleWithdrawals,
                    currencyCode: currencyCode
                )
            }
            .sheet(item: $selectedAssociatedExpense) { expense in
                TransactionEditView(transaction: expense)
            }
            .sheet(isPresented: $showReceiptCamera) {
                ImagePickerView(sourceType: .camera) { image in
                    _ = try? ReceiptAttachmentStore.addImage(image, to: transaction, in: modelContext)
                }
            }
            .sheet(isPresented: $showReceiptLibrary) {
                ImagePickerView(sourceType: .photoLibrary) { image in
                    _ = try? ReceiptAttachmentStore.addImage(image, to: transaction, in: modelContext)
                }
            }
            .sheet(isPresented: Binding(
                get: { previewURL != nil },
                set: { if !$0 { previewURL = nil } }
            )) {
                if let previewURL {
                    ReceiptPreviewContainerSheet(url: previewURL)
                }
            }
            .fileImporter(
                isPresented: $showReceiptPDFPicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                urls.forEach { url in
                    _ = try? ReceiptAttachmentStore.addFile(from: url, to: transaction, in: modelContext)
                }
            }
            .onAppear { loadTransaction() }
        }
    }

    // MARK: - Recurrence Insight

    private var shouldShowRecurrenceInsight: Bool {
        transaction.recurrenceType == .monthly &&
        transaction.installmentGroupId != nil &&
        !recurrenceAmountPoints.isEmpty
    }

    private var sortedReceiptAttachments: [ReceiptAttachment] {
        (transaction.receiptAttachments ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    private var recurrenceAmountPoints: [RecurrenceAmountPoint] {
        guard transaction.recurrenceType == .monthly,
              let groupId = transaction.installmentGroupId else { return [] }

        let calendar = Calendar.current
        let group = fetchGroup(groupId)
            .filter { $0.recurrenceType == .monthly }

        guard let currentMonth = calendar.dateInterval(of: .month, for: transaction.date)?.start else {
            return []
        }

        return (-3...3).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: currentMonth) else {
                return nil
            }

            if offset == 0 {
                return RecurrenceAmountPoint(
                    date: month,
                    amount: transaction.amount,
                    isForecast: false,
                    isCurrent: true
                )
            }

            let matchingTransaction = group.first { candidate in
                calendar.isDate(candidate.date, equalTo: month, toGranularity: .month) &&
                calendar.isDate(candidate.date, equalTo: month, toGranularity: .year)
            }

            if let matchingTransaction {
                return RecurrenceAmountPoint(
                    date: month,
                    amount: matchingTransaction.amount,
                    isForecast: offset > 0,
                    isCurrent: false
                )
            }

            guard offset > 0 else { return nil }
            return RecurrenceAmountPoint(
                date: month,
                amount: transaction.amount,
                isForecast: true,
                isCurrent: false
            )
        }
    }

    private var recurrenceInsightCard: some View {
        let points       = recurrenceAmountPoints
        let historical   = points.filter { !$0.isForecast }
        let forecast     = points.filter { $0.isCurrent || $0.isForecast }
        let current      = points.first { $0.isCurrent }
        let previous     = points.last  { !$0.isForecast && !$0.isCurrent }
        let selectedPoint = selectedRecurrencePoint(in: points) ?? current

        let amounts  = points.map(\.amount)
        let padding  = (amounts.max() ?? 1) * 0.18
        let yMin     = max(0, (amounts.min() ?? 0) - padding)
        let yMax     = (amounts.max() ?? 1) + padding * 3.2   // espaço para o tooltip

        let delta: Double? = {
            guard let c = current, let p = previous, p.amount > 0 else { return nil }
            return (c.amount - p.amount) / p.amount * 100
        }()

        return VStack(alignment: .leading, spacing: 14) {

            // ── Cabeçalho ──────────────────────────────────────────────
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("transaction.recurrenceHistory"))
                        .font(.subheadline.weight(.semibold))
                    if let delta {
                        let sign: String = delta >= 0 ? "+" : ""
                        let color: Color = delta > 2 ? .red : delta < -2 ? .green : .secondary
                        Text(t("transaction.vsPreviousMonth", "\(sign)\(String(format: "%.0f", delta))"))
                            .font(.caption)
                            .foregroundStyle(color)
                    } else {
                        Text(t("transaction.monthlyRecurrence"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // Legenda compacta no cabeçalho
                HStack(spacing: 10) {
                    recurrenceLegendItem(color: .green,  dashed: false, label: t("dashboard.done"))
                    recurrenceLegendItem(color: .orange, dashed: true,  label: t("dashboard.forecast"))
                }
            }

            // ── Gráfico ────────────────────────────────────────────────
            Chart {
                // Área preenchida sob a linha histórica
                ForEach(historical) { point in
                    AreaMark(
                        x: .value("Mês", point.date),
                        yStart: .value("Base",  yMin),
                        yEnd:   .value("Valor", point.amount)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.12), Color.accentColor.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }

                // Linha histórica — sólida, azul
                ForEach(historical) { point in
                    LineMark(
                        x: .value("Mês", point.date),
                        y: .value("Valor", point.amount)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }

                // Linha de previsão — pontilhada, azul (mesma cor, estilo diferente)
                ForEach(forecast) { point in
                    LineMark(
                        x: .value("Mês", point.date),
                        y: .value("Valor", point.amount)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 5]))
                }

                // Pontos — verde = realizado, laranja = previsão
                ForEach(points) { point in
                    PointMark(
                        x: .value("Mês", point.date),
                        y: .value("Valor", point.amount)
                    )
                    .symbolSize(point.isCurrent ? 60 : 36)
                    .foregroundStyle(point.isForecast && !point.isCurrent ? Color.orange : Color.green)
                }

                // Ponto selecionado + tooltip
                if let sel = selectedPoint {
                    PointMark(
                        x: .value("Mês",   sel.date),
                        y: .value("Valor", sel.amount)
                    )
                    .symbolSize(140)
                    .foregroundStyle(sel.isForecast && !sel.isCurrent ? Color.orange : Color.green)
                    .annotation(
                        position: recurrenceAnnotationPosition(for: sel, in: points),
                        alignment: .center
                    ) {
                        recurrenceTooltip(for: sel)
                    }
                }
            }
            .frame(height: 160)
            .chartYScale(domain: yMin...yMax)
            .chartYAxis(.hidden)
            // padding: 20 garante que os pontos nas bordas ficam afastados das extremidades,
            // e os labels do eixo X ficam exatamente alinhados abaixo de cada ponto
            .chartXScale(range: .plotDimension(padding: 20))
            .chartXAxis {
                AxisMarks(values: points.map(\.date)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            let isCur = points.first(where: {
                                Calendar.current.isDate($0.date, equalTo: date, toGranularity: .month)
                            })?.isCurrent == true
                            Text(monthLabel(date, style: .abbreviated))
                                .font(.caption2.weight(isCur ? .bold : .regular))
                                .foregroundStyle(isCur ? Color.primary : Color.secondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in   // onChanged → tooltip em tempo real
                                    selectNearestRecurrencePoint(
                                        to: value.location,
                                        proxy: proxy,
                                        geometry: geometry,
                                        points: points
                                    )
                                }
                        )
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Recurrence chart helpers

    @ViewBuilder
    private func recurrenceTooltip(for point: RecurrenceAmountPoint) -> some View {
        VStack(spacing: 2) {
            Text(monthLabel(point.date, style: .wide))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(point.amount.asCurrency(currencyCode))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(point.isForecast && !point.isCurrent ? Color.orange : Color.primary)
            if point.isForecast && !point.isCurrent {
                Text(t("transaction.forecastLowercase"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    @ViewBuilder
    private func recurrenceLegendItem(color: Color, dashed: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            if dashed {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(color)
                            .frame(width: 4, height: 2)
                    }
                }
            } else {
                Capsule()
                    .fill(color)
                    .frame(width: 14, height: 2)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func recurrenceAnnotationPosition(
        for point: RecurrenceAmountPoint,
        in points: [RecurrenceAmountPoint]
    ) -> AnnotationPosition {
        guard let idx = points.firstIndex(where: { $0.id == point.id }) else { return .top }
        if idx == 0               { return .topTrailing }
        if idx == points.count - 1 { return .topLeading }
        return .top
    }

    private func selectedRecurrencePoint(in points: [RecurrenceAmountPoint]) -> RecurrenceAmountPoint? {
        guard let selectedRecurrenceMonth else { return nil }
        return points.first {
            Calendar.current.isDate($0.date, equalTo: selectedRecurrenceMonth, toGranularity: .month) &&
            Calendar.current.isDate($0.date, equalTo: selectedRecurrenceMonth, toGranularity: .year)
        }
    }

    private func selectNearestRecurrencePoint(
        to location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [RecurrenceAmountPoint]
    ) {
        guard let plotFrameAnchor = proxy.plotFrame else { return }
        let plotFrame = geometry[plotFrameAnchor]
        guard plotFrame.contains(location) else { return }
        let xPosition = location.x - plotFrame.origin.x
        guard let tappedDate: Date = proxy.value(atX: xPosition) else { return }

        let nearest = points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(tappedDate)) < abs(rhs.date.timeIntervalSince(tappedDate))
        }
        selectedRecurrenceMonth = nearest?.date
    }

    private func monthLabel(_ date: Date, style: RecurrenceMonthLabelStyle) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = style == .wide ? "LLLL yyyy" : "LLL"
        return formatter.string(from: date).capitalized
    }

    @ViewBuilder
    private func compactActionBadge(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }

    private func associateNewCashExpense(_ expense: Transaction) {
        guard expense.type == .expense else { return }
        guard expense.account?.type == .cash else { return }
        guard expense.parentCashWithdrawal == nil else { return }
        guard expense.amount <= transaction.remainingCashAmount + 0.009 else { return }

        let allocation = CashWithdrawalAllocation(
            allocatedAmount: expense.amount,
            withdrawalTransaction: transaction,
            expenseTransaction: expense
        )
        modelContext.insert(allocation)
    }

    private func removeCashWithdrawalAssociation() {
        guard let allocation = (transaction.incomingCashAllocations ?? []).first else { return }
        modelContext.delete(allocation)
    }

    // MARK: - Load

    private func loadTransaction() {
        amountText              = String(format: "%.2f", transaction.amount)
        placeName               = transaction.placeName ?? ""
        date                    = transaction.date
        selectedAccount         = transaction.account
        selectedCategory        = transaction.category
        selectedSubcategory     = transaction.subcategory
        notes                   = transaction.notes ?? ""
        isPaid                  = transaction.isPaid
        editedRecurrenceType    = transaction.recurrenceType
        editedInstallmentTotal  = transaction.installmentTotal ?? 2
        if let ccId = transaction.costCenterId {
            selectedCostCenter = costCenters.first { $0.id == ccId }
        }
    }

    // MARK: - Save

    private func save(scope: RecurrenceEditScope) {
        let normalized = amountText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        let newAmount = Double(normalized).flatMap { $0 >= 0 ? $0 : nil } ?? transaction.amount

        // Data e isPaid só afetam esta ocorrência, independente do escopo
        transaction.date   = date
        transaction.isPaid = isPaid

        switch scope {
        case .thisOnly:
            apply(to: transaction, amount: newAmount)

        case .thisAndFuture:
            guard let groupId    = transaction.installmentGroupId,
                  let currentIdx = transaction.installmentIndex else {
                apply(to: transaction, amount: newAmount); break
            }
            fetchGroup(groupId)
                .filter { ($0.installmentIndex ?? 0) >= currentIdx }
                .forEach { apply(to: $0, amount: newAmount) }

        case .all:
            guard let groupId = transaction.installmentGroupId else {
                apply(to: transaction, amount: newAmount); break
            }
            fetchGroup(groupId).forEach { apply(to: $0, amount: newAmount) }
        }

        // If recurrence was changed on a standalone transaction, generate the series now.
        // (Transactions already in a series keep their existing recurrence structure.)
        if !isInRecurrenceSeries && editedRecurrenceType != .none {
            transaction.recurrenceType = editedRecurrenceType
            switch editedRecurrenceType {
            case .installment:
                Transaction.generateInstallments(
                    from: transaction,
                    total: editedInstallmentTotal,
                    in: modelContext
                )
            case .monthly:
                Transaction.generateMonthlyRecurrences(
                    from: transaction,
                    in: modelContext
                )
            case .annual:
                Transaction.generateAnnualRecurrences(
                    from: transaction,
                    in: modelContext
                )
            case .none:
                break
            }
        }

        dismiss()
    }

    /// Aplica os campos editáveis (valor, local, conta, categoria, notas) a uma transação.
    /// Data e isPaid são intencionalmente excluídos — cada ocorrência tem os seus.
    private func apply(to tx: Transaction, amount: Double) {
        tx.amount       = amount
        tx.placeName    = placeName.isEmpty ? nil : placeName
        tx.account      = selectedAccount
        tx.notes        = notes.isEmpty ? nil : notes
        if tx.kind == .cardBillPayment || tx.kind == .cashWithdrawal {
            tx.category = nil
            tx.subcategory = nil
            tx.costCenterId = nil
        } else {
            tx.category = selectedCategory
            tx.subcategory = selectedSubcategory
            tx.costCenterId = selectedCostCenter?.id
        }
    }

    private func allocationMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
        }
    }

    private func delete(scope: RecurrenceEditScope) {
        switch scope {
        case .thisOnly:
            ReceiptAttachmentStore.cleanupFiles(for: transaction)
            modelContext.delete(transaction)

        case .thisAndFuture:
            guard let groupId = transaction.installmentGroupId,
                  let currentIdx = transaction.installmentIndex else {
                ReceiptAttachmentStore.cleanupFiles(for: transaction)
                modelContext.delete(transaction)
                break
            }

            fetchGroup(groupId)
                .filter { ($0.installmentIndex ?? 0) >= currentIdx }
                .forEach {
                    ReceiptAttachmentStore.cleanupFiles(for: $0)
                    modelContext.delete($0)
                }

        case .all:
            guard let groupId = transaction.installmentGroupId else {
                ReceiptAttachmentStore.cleanupFiles(for: transaction)
                modelContext.delete(transaction)
                break
            }

            fetchGroup(groupId).forEach {
                ReceiptAttachmentStore.cleanupFiles(for: $0)
                modelContext.delete($0)
            }
        }

        dismiss()
    }

    /// Retorna todas as transações do mesmo grupo de recorrência.
    private func fetchGroup(_ groupId: UUID) -> [Transaction] {
        let all = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        return all.filter { $0.installmentGroupId == groupId }
    }
}
