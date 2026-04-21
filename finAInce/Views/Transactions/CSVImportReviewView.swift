import SwiftUI
import SwiftData

// MARK: - Import Phase

enum CSVImportPhase {
    case selectAccount  // user picks the bank account before processing starts
    case reading        // parsing file and running reconciliation check
    case reviewing      // results ready for the user to review
}

// MARK: - Import List Filter

enum ImportListFilter: Hashable, CaseIterable {
    case newOnly, reconciled, all
}


// MARK: - CSVImportReviewView

struct CSVImportReviewView: View {
 
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showExitAlert = false
    
    @Query(sort: \Transaction.date, order: .reverse) private var existingTransactions: [Transaction]
    @Query private var categories: [Category]
    @Query(sort: \Account.createdAt) private var accounts: [Account]

    @AppStorage("app.currencyCode") private var currencyCode = "BRL"

    let csvURL: URL
    var initialAccountId: UUID? = nil
    var onDismissSheet: (() -> Void)? = nil

    @State private var phase:             CSVImportPhase   = .selectAccount
    @State private var items:             [ImportedTransaction] = []
    @State private var errorMessage:      String?          = nil
    @State private var selectedAccountId: UUID?            = nil
    @State private var activeFilter:      ImportListFilter = .newOnly
    @State private var importBanner:      String?          = nil

    // Bulk edit
    @State private var isBulkMode            = false
    @State private var searchText            = ""
    @State private var bulkSelectedIds:      Set<UUID> = []
    @State private var showBulkCategorySheet = false
    @State private var bulkCategory:         Category? = nil
    @State private var bulkSubcategory:      Category? = nil
    @State private var initialOrder: [UUID] = []
    
    //Agrupamento por similares ou listagem por data
    enum GroupingMode {
        case date
        case merchant
    }
    @State private var groupingMode: GroupingMode = .date

    
    private var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountId }
    }

    // MARK: - Body

    var body: some View {
        content
            .navigationTitle(t("csv.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .reviewing = phase, !items.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(t("csv.importCount", actionableCount)) {
                            importSelected()
                        }
                        .fontWeight(.semibold)
                        .disabled(actionableCount == 0)
                    }
                }
            }
            .onAppear {
                restoreSelectedAccountIfNeeded()
            }
            .onChange(of: accounts.count) { _, _ in
                restoreSelectedAccountIfNeeded()
            }
            .onChange(of: selectedAccountId) { _, newValue in
                persistImportSummary(accountIdOverride: newValue)
            }
           .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Phase routing

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .selectAccount: accountPickerView
        case .reading:       loadingView(caption: t("csv.reading"))
        case .reviewing:     reviewContent
        }
    }

    private func loadingView(caption: String) -> some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Account Picker Phase

    private var accountPickerView: some View {
        VStack(spacing: 0) {
            // Hero
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text(t("import.accountPickerTitle"))
                    .font(.title2.bold())
                Text(t("import.accountPickerSubtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 36)
            .padding(.bottom, 24)

            List {
                ForEach(accounts) { account in
                    Button { selectedAccountId = account.id } label: {
                        HStack(spacing: 14) {
                            Image(systemName: account.icon)
                                .font(.title3)
                                .foregroundStyle(Color(hex: account.color))
                                .frame(width: 44, height: 44)
                                .background(Color(hex: account.color).opacity(0.12))
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name).font(.body.weight(.medium))
                                if account.isDefault {
                                    Text(t("account.default"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selectedAccountId == account.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor).font(.title3)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)

            Button {
                Task { await process() }
            } label: {
                Label(t("import.startVerification"), systemImage: "arrow.right.circle.fill")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedAccountId == nil)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.systemBackground).ignoresSafeArea())
            .alert("Sair da importação?", isPresented: $showExitAlert) { //todo: localizar
                Button("Cancelar", role: .cancel) {}
                Button("Sair", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("Você perderá o progresso da importação.") //todo: localizar
            }
            .toolbar(.hidden, for: .tabBar)
        }
    }

    
    private var groupedByMerchant: [(key: String, indices: [Int])] {
        let grouped = Dictionary(grouping: filteredIndices) { i in
            items[i].rawDescription.normalizedForMatching()
        }

        return grouped
            .map { (key, indices) in
                let sortedIndices = indices.sorted {
                    let id0 = items[$0].id
                    let id1 = items[$1].id
                    
                    let pos0 = initialOrder.firstIndex(of: id0) ?? 0
                    let pos1 = initialOrder.firstIndex(of: id1) ?? 0
                    
                    return pos0 < pos1
                }
                return (key, sortedIndices)
            }
            .sorted { lhs, rhs in
                lhs.indices.first ?? 0 < rhs.indices.first ?? 0
            }
    }
    
    // MARK: - Review Content

    @ViewBuilder
    private var reviewContent: some View {
        if items.isEmpty {
            emptyState
        } else {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // ── Success banner ──────────────────────────────────────
                    if let banner = importBanner {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                            Text(banner)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.green)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .id(banner)
                    }
                  
                    groupByBar
                    filterBar
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    bulkModeBar          // "Categorizar vários" ↔ "Cancelar"
                    if isBulkMode {
                        searchBar        // só visível em modo bulk
                    }
                    Divider()
                    reviewList
                        .safeAreaInset(edge: .bottom) {
                            if isBulkMode && !bulkSelectedIds.isEmpty {
                                Color.clear.frame(height: 120)
                            }
                        }
                }
                if isBulkMode && !bulkSelectedIds.isEmpty {
                    bulkActionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isBulkMode)
            .animation(.easeInOut(duration: 0.2), value: bulkSelectedIds.isEmpty)
            .animation(.easeInOut(duration: 0.3), value: importBanner)
            .sheet(isPresented: $showBulkCategorySheet, onDismiss: applyBulkCategory) {
                CategoryPickerSheet(
                    selectedCategory: $bulkCategory,
                    selectedSubcategory: $bulkSubcategory,
                    transactionType: .expense
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: errorMessage == nil ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(errorMessage == nil
                    ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
            if let error = errorMessage {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            } else {
                Text(t("csv.noTransactions")).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filter counts

    private var newCount:        Int { items.filter { !$0.alreadyImported }.count }
    private var reconciledCount: Int { items.filter {  $0.alreadyImported }.count }
    private var allCount:        Int { items.count }

    // MARK: - Bulk Mode Toggle Bar

    private var bulkModeBar: some View {
        HStack {
            if isBulkMode {
                Text(bulkSelectedIds.isEmpty
                     ? "Selecione as transações"
                     : "\(bulkSelectedIds.count) selecionada\(bulkSelectedIds.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if isBulkMode { exitBulkMode() } else { enterBulkMode() }
                }
            } label: {
                if isBulkMode {
                    Text(t("common.cancel"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Label(t("import.categorizeMany"), systemImage: "tag.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private func enterBulkMode() {
        isBulkMode     = true
        searchText     = ""
        bulkSelectedIds.removeAll()
    }

    private func exitBulkMode() {
        isBulkMode     = false
        searchText     = ""
        bulkSelectedIds.removeAll()
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            TextField(t("common.search"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) { _, _ in
                    // Clear bulk selection when search changes so stale IDs don't linger
                    bulkSelectedIds.removeAll()
                }
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        Picker("", selection: $activeFilter) {
            Text("\(t("import.filterNew")) (\(newCount))")
                .tag(ImportListFilter.newOnly)
            Text("\(t("import.filterReconciled")) (\(reconciledCount))")
                .tag(ImportListFilter.reconciled)
            Text("\(t("import.filterAll")) (\(allCount))")
                .tag(ImportListFilter.all)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
    
    //Toogle de agrupamento no topo
    private var groupByBar: some View {
        Picker("", selection: $groupingMode) {
            Text("Por data").tag(GroupingMode.date)
            Text("Similares").tag(GroupingMode.merchant)
        }
        .pickerStyle(.segmented) // 🔥 ESSENCIAL
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    

    // MARK: - Review List

    private var filteredIndices: [Int] {
        items.indices.filter { i in
            let item = items[i]
            let passesTab: Bool
            switch activeFilter {
            case .newOnly:    passesTab = !item.alreadyImported || item.isSelected
            case .reconciled: passesTab =  item.alreadyImported
            case .all:        passesTab = true
            }
            guard passesTab else { return false }
            guard !searchText.isEmpty else { return true }
            let q = searchText.lowercased()
            return item.rawDescription.lowercased().contains(q)
        }
    }

    
    @ViewBuilder
    private func merchantHeader(group: (key: String, indices: [Int])) -> some View {
        let firstItem = items[group.indices.first!]
        
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(firstItem.rawDescription)
                    .font(.subheadline.bold())
                
                Text("\(group.indices.count) transações")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                applyCategoryToGroup(indices: group.indices)
            } label: {
                Label("Categorizar", systemImage: "tag")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func applyCategoryToGroup(indices: [Int]) {
        bulkSelectedIds = Set(indices.map { items[$0].id })
        showBulkCategorySheet = true
    }
    
    /// Number of non-reconciled items currently visible (eligible for bulk actions).
    private var filteredEligibleCount: Int {
        filteredIndices.filter { !items[$0].alreadyImported }.count
    }

    @ViewBuilder
    private func rowView(_ i: Int) -> some View {
        let isBulkChecked = bulkSelectedIds.contains(items[i].id)

        HStack(alignment: .top, spacing: 0) {

            // Checkbox
            if isBulkMode && !items[i].alreadyImported {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isBulkChecked { bulkSelectedIds.remove(items[i].id) }
                        else             { bulkSelectedIds.insert(items[i].id) }
                    }
                } label: {
                    Image(systemName: isBulkChecked
                          ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isBulkChecked
                            ? Color.accentColor : Color(.tertiaryLabel))
                        .frame(width: 30)
                        .padding(.top, 12)
                        .padding(.trailing, 4)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            ImportedTransactionRow(
                item: $items[i],
                isBulkMode: isBulkMode,
                existingTransactions: existingTransactions,
                currencyCode: currencyCode,
                findSessionMatch: { rowItem in
                    findSessionMatch(for: rowItem)
                },
                onCategoryResolved: { cat, sub, merchantName in
                    propagateCategory(
                        fromIndex: i,
                        resolvedMerchantName: merchantName,
                        rawDescription: items[i].rawDescription,
                        category: cat,
                        subcategory: sub
                    )
                }
            )
        }
        .animation(.easeInOut(duration: 0.25), value: isBulkMode)
    }
    
    private var reviewList: some View {
        List {
            
            // ─────────────────────────────
            // MODO POR DATA (padrão)
            // ─────────────────────────────
            if groupingMode == .date {
                Section {
                    ForEach(filteredIndices, id: \.self) { i in
                        rowView(i)
                    }
                } header: {
                    Text(t("csv.detected", items.count, selectedCount))
                }
            }
            
            // ─────────────────────────────
            // MODO SIMILARES (AGRUPADO)
            // ─────────────────────────────
            else {
                ForEach(groupedByMerchant, id: \.key) { group in
                    Section {
                        ForEach(group.indices, id: \.self) { i in
                            rowView(i)
                        }
                    } header: {
                        merchantHeader(group: group)
                    }
                }
            }

            // ── erro ──
            if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Bulk Action Bar

    private var bulkActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 10) {
                // Select all / deselect all
                HStack(spacing: 0) {
                    Button {
                        withAnimation {
                            bulkSelectedIds = Set(
                                filteredIndices.compactMap { !items[$0].alreadyImported ? items[$0].id : nil }
                            )
                        }
                    } label: {
                        Text(t("import.selectAllCount", filteredEligibleCount))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Button {
                        withAnimation { bulkSelectedIds.removeAll() }
                    } label: {
                        Text(t("import.deselectAll"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)

                // Category action button
                Button { showBulkCategorySheet = true } label: {
                    let n = bulkSelectedIds.count
                    Label(t("import.categorizeCount", n),
                          systemImage: "tag.fill")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .padding(.top, 10)
            .background(Color(.systemBackground).ignoresSafeArea())
        }
    }

    // MARK: - Apply Bulk Category

    private func applyBulkCategory() {
        guard let cat = bulkCategory else { return }
        for i in items.indices where bulkSelectedIds.contains(items[i].id) {
            items[i].resolvedCategory    = cat
            items[i].resolvedSubcategory = bulkSubcategory
            items[i].matchDecision       = .createNew
            items[i].isSelected          = true
        }
        bulkSelectedIds.removeAll()
        bulkCategory    = nil
        bulkSubcategory = nil
    }

    private func findSessionMatch(for item: ImportedTransaction) -> ImportedTransaction? {
        let currentNormalized = item.rawDescription.normalizedForMatching()

        return items.first { other in
            guard other.id != item.id else { return false }
            guard other.resolvedCategory != nil else { return false }

            let otherNormalized = other.rawDescription.normalizedForMatching()
            return currentNormalized == otherNormalized
        }
    }

    // MARK: - Category Propagation

    /// Propagates a resolved category to other rows in the same import batch
    /// that belong to the same merchant.
    ///
    /// Matching strategy:
    /// - If an AI-cleaned merchant name is available (`resolvedMerchantName`), use it
    ///   for token matching against other rows' raw descriptions. This is reliable
    ///   because the AI name is a clean brand name (e.g. "Cinemark") with no bank noise.
    /// - If only a raw description is available (manual pick, no AI), do NOT propagate.
    ///   Raw bank descriptions share too many noise tokens ("PAGO", "MOVIL", "TARJ",
    ///   card numbers, etc.) that would incorrectly match unrelated merchants.
    private func propagateCategory(
        fromIndex: Int,
        resolvedMerchantName: String?,
        rawDescription: String?,
        category: Category,
        subcategory: Category?
    ) {
        //desabilitando por enquando a funcao ate ela ficar estavel
        return
        
        // Require a clean AI-extracted merchant name — never propagate from raw bank text
        guard let cleanName = rawDescription,
              !cleanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        

        let sourceNormalized = cleanName.normalizedForMatching()

        for i in items.indices where i != fromIndex {
            let row = items[i]
            guard !row.alreadyImported,
                  row.resolvedCategory == nil,
                  row.matchDecision != .useMatch,
                  row.matchDecision != .linkToExisting
            else { continue }

            guard let otherName = row.resolvedMerchantName else { continue }
            let otherNormalized = otherName.normalizedForMatching()

            // 🔥 Only propagate when normalized merchant matches EXACTLY
            guard sourceNormalized == otherNormalized else { continue }

            items[i].resolvedCategory    = category
            items[i].resolvedSubcategory = subcategory
            items[i].matchDecision       = .createNew
            items[i].isSelected          = true
            
            
            print("PROPAGATE FROM:", resolvedMerchantName ?? "nil")
            print("TO:", otherName)
        }
    }

    // MARK: - Computed counts

    var actionableCount: Int { items.filter { $0.isSelected && !$0.alreadyImported }.count }
    var selectedCount:   Int { actionableCount }

    // MARK: - Process

    func process() async {
        phase = .reading
        
        initialOrder = items.map { $0.id }
        
        let rows: [[String]]
        do {
            rows = try CSVImportService.readFile(from: csvURL)
        } catch {
            errorMessage = error.localizedDescription
            items = []; phase = .reviewing; return
        }

        guard let map = CSVImportService.detectColumns(in: rows) else {
            errorMessage = t("csv.errorColumns")
            items = []; phase = .reviewing; return
        }

        let parsed = CSVImportService.extractTransactions(from: rows, columns: map)
        guard !parsed.isEmpty else {
            errorMessage = nil
            items = []
            phase = .reviewing
            persistImportSummary()
            return
        }

        // Scope to the selected account — all matching logic is account-scoped
        let accountTransactions = existingTransactions.filter {
            $0.account?.id == selectedAccountId
        }
        let cal = Calendar.current

        items = parsed.map { item in
            var mutable = item
            
            // 🧨 RESET para evitar vazamento de dados entre linhas
            mutable.resolvedMerchantName = nil
            mutable.resolvedCategory = nil
            mutable.resolvedSubcategory = nil
            
            mutable.isSelected    = false
            mutable.matchDecision = .undecided

            let hash = ImportedTransaction.makeHash(date: item.date,
                                                    description: item.rawDescription,
                                                    amount: item.amount)

            // ── Regra 1: Hash duplicado exato ────────────────────────────────
            // Mesmo hash do arquivo atual: já foi importada antes, então vai
            // direto para "Importadas/Conciliadas".
            if let exactHashMatch = accountTransactions
                .filter({ $0.importHash == hash })
                .max(by: { $0.date < $1.date }) {
                mutable.alreadyImported       = true
                mutable.existingTransactionId = exactHashMatch.id
                return mutable
            }

            // ── Regra 2: Match direto por valor + proximidade de data ────────
            // Busca na mesma conta transações cujo valor seja igual.
            // Mesmo que já tenham importHash antigo/diferente, ainda podem ser
            // candidatas à conciliação automática.
            // (diferença < 0,5%).
            // Prioridade:
            //   Score 1,00 — mesmo dia  → match quase certo
            //   Score 0,85 — ±3 dias   → match muito próximo
            // Se mais de um candidato, escolhe o de maior score; empate → menor diff de dias.
            let candidates = accountTransactions.filter { tx in
                let pct = abs(tx.amount - item.amount) / max(item.amount, 0.01)
                return pct < 0.005   // < 0,5 % de diferença de valor
            }

            typealias Scored = (tx: Transaction, score: Double, dayDiff: Int)
            let scored: [Scored] = candidates.compactMap { tx in
                let diff = cal.dateComponents(
                    [.day],
                    from: cal.startOfDay(for: tx.date),
                    to:   cal.startOfDay(for: item.date)
                ).day ?? Int.max
                let absDiff = abs(diff)
                if absDiff == 0      { return (tx, 1.00, absDiff) }
                else if absDiff <= 3 { return (tx, 0.85, absDiff) }
                return nil
            }

            if let best = scored.max(by: { a, b in
                a.score != b.score ? a.score < b.score : a.dayDiff > b.dayDiff
            }) {
                // Match automático: chip "Auto" pré-selecionado, usuário confirma com "Importar"
                mutable.resolvedMerchantName     = best.tx.placeName
                mutable.recommendedTransactionId = best.tx.id
                mutable.resolvedCategory         = best.tx.category
                mutable.resolvedSubcategory      = best.tx.subcategory
                mutable.matchDecision            = .useMatch
                mutable.isSelected               = true
                
                print("RAW:", item.rawDescription)
                print("MERCHANT:", mutable.resolvedMerchantName ?? "nil")
                
                return mutable
            }

            // ── Regra 3: Sem match → "Nova" ──────────────────────────────────
            // Usuário decide: criar nova (IA sugere categoria) ou associar manualmente.
            return mutable
        }

        phase = .reviewing
        persistImportSummary()
    }

    // MARK: - Import Selected

    func importSelected() {
        let account = selectedAccount
        var importedCount = 0

        for i in items.indices where items[i].isSelected && !items[i].alreadyImported {
            let item = items[i]
            let hash = ImportedTransaction.makeHash(date: item.date,
                                                    description: item.rawDescription,
                                                    amount: item.amount)
            var resolvedId: UUID? = nil

            switch item.matchDecision {

            case .linkToExisting:
                if let linkedId = item.linkedTransactionId,
                   let existing = existingTransactions.first(where: { $0.id == linkedId }) {
                    existing.amount     = item.amount
                    existing.date       = item.date
                    existing.isPaid     = true
                    existing.importHash = hash
                    resolvedId = existing.id
                }

            case .useMatch:
                if let repId = item.recommendedTransactionId,
                   let existing = existingTransactions.first(where: { $0.id == repId }) {
                    existing.amount     = item.amount
                    existing.date       = item.date
                    existing.isPaid     = true
                    existing.importHash = hash
                    resolvedId = existing.id
                } else {
                    let tx = Transaction(
                        type: .expense,
                        amount: item.amount,
                        date: item.date,
                        placeName: item.effectivePlaceName,
                        notes: item.notes.isEmpty ? nil : item.notes
                    )
                    tx.category    = item.resolvedCategory ?? categories.first { $0.name == item.match?.categoryName }
                    tx.subcategory = item.resolvedSubcategory
                    tx.account     = account
                    tx.importHash  = hash
                    modelContext.insert(tx)
                }

            default:
                let tx = Transaction(
                    type: .expense,
                    amount: item.amount,
                    date: item.date,
                    placeName: item.effectivePlaceName,
                    notes: item.notes.isEmpty ? nil : item.notes
                )
                tx.category    = item.resolvedCategory
                tx.subcategory = item.resolvedSubcategory
                tx.account     = account
                tx.importHash  = hash
                modelContext.insert(tx)
            }

            // Move this row to the "Reconciled" tab in the local list
            items[i].alreadyImported       = true
            items[i].isSelected            = false
            items[i].matchDecision         = .undecided
            if let id = resolvedId {
                items[i].existingTransactionId = id
            }
            importedCount += 1
        }

        guard importedCount > 0 else { return }

        // Show success banner and auto-dismiss after 3 s
        let noun = importedCount == 1 ? "transação importada" : "transações importadas"
        withAnimation(.easeInOut(duration: 0.3)) {
            importBanner = "\(importedCount) \(noun) e conciliada\(importedCount == 1 ? "" : "s")"
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.3)) { importBanner = nil }
        }

        persistImportSummary()
    }

    private func persistImportSummary(accountIdOverride: UUID? = nil) {
        try? ImportStatementStore.updateSummary(
            fileName: csvURL.lastPathComponent,
            accountId: accountIdOverride ?? selectedAccountId,
            totalCount: items.count,
            newCount: items.filter { !$0.alreadyImported }.count,
            reconciledCount: items.filter { $0.alreadyImported }.count
        )
    }

    private func restoreSelectedAccountIfNeeded() {
        if let initialAccountId,
           accounts.contains(where: { $0.id == initialAccountId }) {
            guard selectedAccountId != initialAccountId || (phase == .selectAccount && items.isEmpty) else { return }
            selectedAccountId = initialAccountId
            if phase == .selectAccount && items.isEmpty {
                Task { await process() }
            }
            return
        }

        guard selectedAccountId == nil else { return }

        if accounts.count == 1 {
            selectedAccountId = accounts.first?.id
        } else {
            selectedAccountId = accounts.first(where: { $0.isDefault })?.id
        }
    }
}

// MARK: - ImportedTransactionRow

struct ImportedTransactionRow: View {
    @Binding var item: ImportedTransaction
    var isBulkMode:           Bool = false
    let existingTransactions: [Transaction]
    let currencyCode:         String
    var findSessionMatch: ((ImportedTransaction) -> ImportedTransaction?)? = nil

    /// Called whenever a category is resolved for this row (from history, AI, or manual picker).
    /// The parent uses this to propagate the category to other rows with the same merchant.
    var onCategoryResolved: ((Category, Category?, String?) -> Void)? = nil

    @Query private var allCategories: [Category]
    @Query private var aiSettings:    [AISettings]

    @State private var showLinkSheet           = false
    @State private var showCategorySheet       = false
    @State private var transactionToPreview:   Transaction? = nil
    @State private var isLoadingAICategory     = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ─────────────────────────────────────────
            HStack(alignment: .center, spacing: 12) {
                if item.alreadyImported {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .frame(width: 31, height: 31)
                } else if !isBulkMode {
                    Toggle("", isOn: $item.isSelected)
                        .labelsHidden()
                        .onChange(of: item.isSelected) { _, isOn in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isOn {
                                    // Default to "Nova" when user enables without choosing a decision
                                    if item.matchDecision == .undecided {
                                        item.matchDecision = .createNew
                                        triggerAICategoryIfNeeded()
                                    }
                                } else {
                                    // Turning the toggle OFF clears the decision
                                    item.matchDecision       = .undecided
                                    item.linkedTransactionId = nil
                                }
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.amount.asCurrency(currencyCode)).font(.headline)
                        if item.alreadyImported {
                            Text(t("import.alreadyImported"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.green, in: Capsule())
                        }
                    }
                    Text(item.rawDescription)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(item.date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)

            // ── Category indicator (bulk mode only) ──
            if isBulkMode, !item.alreadyImported, let cat = item.resolvedCategory {
                HStack(spacing: 6) {
                    Image(systemName: cat.icon)
                        .font(.caption2.bold())
                        .foregroundStyle(Color(hex: cat.color))
                        .frame(width: 20, height: 20)
                        .background(Color(hex: cat.color).opacity(0.12))
                        .clipShape(Circle())
                    Text(cat.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(hex: cat.color))
                    if let sub = item.resolvedSubcategory {
                        Text("· \(sub.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── Decision buttons — hidden in bulk mode ──
            if !item.alreadyImported && !isBulkMode {
                decisionButtons
                    .padding(.bottom, item.matchDecision == .undecided ? 6 : 0)

                // ── Expanded detail (only when a decision is active + selected) ──
                if item.isSelected && item.matchDecision != .undecided {
                    expandedDetail
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Reconciled rows open the existing transaction detail on tap
            if item.alreadyImported,
               let txId = item.existingTransactionId,
               let tx = existingTransactions.first(where: { $0.id == txId }) {
                transactionToPreview = tx
            }
        }
        .animation(.easeInOut(duration: 0.2), value: item.isSelected)
        .animation(.easeInOut(duration: 0.2), value: item.matchDecision)
        .sheet(isPresented: $showLinkSheet) {
            LinkTransactionSheet(item: $item,
                                 existingTransactions: existingTransactions,
                                 currencyCode: currencyCode)
        }
        .sheet(isPresented: $showCategorySheet, onDismiss: {
            // Propagate manually-chosen category to other rows in the same batch
            if let cat = item.resolvedCategory {
                onCategoryResolved?(cat, item.resolvedSubcategory, item.resolvedMerchantName)
            }
        }) {
            CategoryPickerSheet(
                selectedCategory: $item.resolvedCategory,
                selectedSubcategory: $item.resolvedSubcategory,
                transactionType: .expense
            )
        }
        .sheet(item: $transactionToPreview) { tx in
            TransactionEditView(transaction: tx)
        }
    }

    // MARK: - Decision Buttons

    private var decisionButtons: some View {
        HStack(spacing: 6) {
            // "Auto" — visível quando process() encontrou um match direto por valor+data
            if item.recommendedTransactionId != nil {
                chipButton(
                    label: t("import.recommended"),
                    systemImage: "sparkles",
                    isActive: item.matchDecision == .useMatch,
                    activeColor: .accentColor
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        item.matchDecision = .useMatch
                        item.isSelected    = true
                    }
                }
            }

            // "Nova"
            chipButton(
                label: t("import.createNew"),
                systemImage: isLoadingAICategory ? "sparkles" : "plus.circle",
                isActive: item.matchDecision == .createNew,
                activeColor: .blue
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    item.matchDecision = .createNew
                    item.isSelected    = true
                }
                triggerAICategoryIfNeeded()
            }

            // "Associar" — sempre visível; abre sheet de busca manual
            chipButton(
                label: t("import.linkExisting"),
                systemImage: "link.circle",
                isActive: item.matchDecision == .linkToExisting,
                activeColor: .orange
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    item.matchDecision = .linkToExisting
                    item.isSelected    = true
                }
                showLinkSheet = true
            }
        }
    }

    // MARK: - Chip Button

    private func chipButton(label: String, systemImage: String,
                            isActive: Bool, activeColor: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? activeColor : Color.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    Capsule().fill(isActive
                        ? activeColor.opacity(0.14)
                        : Color(uiColor: .tertiarySystemBackground))
                )
                .overlay(
                    Capsule().strokeBorder(isActive
                        ? activeColor.opacity(0.35)
                        : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Detail

    @ViewBuilder
    private var expandedDetail: some View {
        switch item.matchDecision {
        case .useMatch:
            autoMatchPreview
                .padding(.top, 8)

        case .createNew:
            categoryPicker
                .padding(.top, 8)

        case .linkToExisting:
            linkPreview
                .padding(.top, 8)

        case .undecided:
            EmptyView()
        }
    }

    // MARK: - Auto Match Preview

    /// Mostra a transação do banco de dados que foi encontrada automaticamente
    /// por valor + data. O usuário pode tocar para abrir o detalhe completo.
    @ViewBuilder
    private var autoMatchPreview: some View {
        if let repId = item.recommendedTransactionId,
           let tx = existingTransactions.first(where: { $0.id == repId }) {

            let iconColor = tx.category.map { Color(hex: $0.color) } ?? Color.accentColor

            Button { transactionToPreview = tx } label: {
                HStack(spacing: 10) {
                    Image(systemName: tx.category?.icon ?? "tag")
                        .font(.subheadline)
                        .foregroundStyle(iconColor)
                        .frame(width: 32, height: 32)
                        .background(iconColor.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tx.placeName ?? tx.category?.name ?? "—")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if let cat = tx.category {
                                Text(cat.name)
                                    .font(.caption)
                                    .foregroundStyle(iconColor)
                                Text("·").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(tx.date, format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(tx.amount.asCurrency(currencyCode))
                            .font(.subheadline.bold())
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Category Picker (opens CategoryPickerSheet)

    private var categoryPicker: some View {
        Button { showCategorySheet = true } label: {
            HStack(spacing: 10) {
                if isLoadingAICategory {
                    ProgressView().scaleEffect(0.75)
                        .frame(width: 30, height: 30)
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption.bold())
                            .foregroundStyle(Color.accentColor)
                        Text(t("import.identifyingCategory"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if let cat = item.resolvedCategory {
                    Image(systemName: cat.icon)
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: cat.color))
                        .frame(width: 30, height: 30)
                        .background(Color(hex: cat.color).opacity(0.12))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cat.name).font(.subheadline.weight(.medium))
                        if let sub = item.resolvedSubcategory {
                            Text(sub.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                } else {
                    Image(systemName: "tag")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Circle())
                    Text(t("transaction.category"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if !isLoadingAICategory {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isLoadingAICategory)
    }

    // MARK: - Link Preview

    @ViewBuilder
    private var linkPreview: some View {
        if let linkedId = item.linkedTransactionId,
           let tx = existingTransactions.first(where: { $0.id == linkedId }) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tx.placeName ?? tx.category?.name ?? "—")
                        .font(.caption.weight(.medium)).lineLimit(1)
                    Text(tx.amount.asCurrency(currencyCode))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showLinkSheet = true
                } label: {
                    Text(t("common.edit")).font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Button {
                showLinkSheet = true
            } label: {
                Label(t("import.linkExisting"), systemImage: "magnifyingglass")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .buttonStyle(.plain)
        }
    }

    // MARK: - Confidence Color

    private func confidenceColor(_ c: Double) -> Color {
        c >= 0.85 ? .green : c >= 0.65 ? .orange : Color(hue: 0.14, saturation: 0.9, brightness: 0.9)
    }


    
    // MARK: - AI Category Suggestion

    /// Triggers category resolution for this row when the user picks "Nova".
    /// Priority:
    ///   1. Historical match — a past transaction with the same merchant already has a category.
    ///   2. AI suggestion    — calls the configured AI provider.
    /// Skips entirely if a category is already set or a request is already in flight.
    private func triggerAICategoryIfNeeded() {
        
        print(item.resolvedCategory);
        
        //guard item.resolvedCategory == nil, !isLoadingAICategory else { return }
    
        // ── 1. Session match (mesma importação) ─────────────────────────────
        let currentNormalized = item.rawDescription.normalizedForMatching()
        
        if let match = findSessionMatch?(item),
           let cat = match.resolvedCategory {

            item.resolvedCategory     = cat
            item.resolvedSubcategory  = match.resolvedSubcategory
            item.resolvedMerchantName = match.resolvedMerchantName

            onCategoryResolved?(cat, match.resolvedSubcategory, match.resolvedMerchantName)
            return
        }
        
        // ── 2. Historical lookup ─────────────────────────────────────────────
        if let historical = findHistoricalCategory() {
            item.resolvedCategory     = historical.category
            item.resolvedSubcategory  = historical.subcategory
            item.resolvedMerchantName = historical.placeName
            onCategoryResolved?(historical.category, historical.subcategory, historical.placeName)
            return
        }

        
        // ── 3. AI fallback ───────────────────────────────────────────────────
        guard let settings = aiSettings.first, settings.isConfigured else { return }
        Task { await fetchAICategory(settings: settings) }
    }

    /// Searches existing transactions for one whose `placeName` shares a significant
    /// token with the current row's raw description. Returns the most recently used
    /// category from that match.
//    private func findHistoricalCategory() -> (category: Category, subcategory: Category?, placeName: String?)? {
//        let rawTokens = merchantTokens(from: item.rawDescription)
//        guard !rawTokens.isEmpty else { return nil }
//
//        let best = existingTransactions
//            .filter { $0.category != nil }
//            .compactMap { tx -> (tx: Transaction, overlap: Int)? in
//                guard let place = tx.placeName, !place.isEmpty else { return nil }
//                let overlap = rawTokens.intersection(merchantTokens(from: place)).count
//                return overlap > 0 ? (tx, overlap) : nil
//            }
//            .max { a, b in
//                // Prefer more overlap; break ties by recency
//                a.overlap != b.overlap ? a.overlap < b.overlap : a.tx.date < b.tx.date
//            }
//
//        guard let match = best, let cat = match.tx.category else { return nil }
//        return (cat, match.tx.subcategory, match.tx.placeName)
//    }
    
    
    private func findHistoricalCategory() -> (category: Category, subcategory: Category?, placeName: String?)? {

        let target = item.rawDescription.normalizedForMatching()
        
        guard !target.isEmpty else { return nil }

        let match = existingTransactions
            .filter { $0.category != nil }
            .compactMap { tx -> Transaction? in
                guard let place = tx.placeName, !place.isEmpty else { return nil }

                let normalizedPlace = place.normalizedForMatching()

                return normalizedPlace == target ? tx : nil
            }
            .max(by: { $0.date < $1.date }) // pega o mais recente

        guard let tx = match, let cat = tx.category else { return nil }

        return (cat, tx.subcategory, tx.placeName)
    }
    
    

    @MainActor
    private func fetchAICategory(settings: AISettings) async {
        isLoadingAICategory = true
        defer { isLoadingAICategory = false }

        let rootCategories = allCategories
            .filter { $0.parent == nil && ($0.type == .expense || $0.type == .both) }
            .sorted { $0.sortOrder < $1.sortOrder }

        let options: [AIService.CategorySuggestionOption] = rootCategories.flatMap { cat in
            let base = AIService.CategorySuggestionOption(categoryName: cat.name, subcategoryName: nil)
            let subs = cat.subcategories.sorted { $0.sortOrder < $1.sortOrder }.map {
                AIService.CategorySuggestionOption(categoryName: cat.name, subcategoryName: $0.name)
            }
            return [base] + subs
        }

        let result: AIService.CategorySuggestionResult?
        do {
            result = try await AIService.suggestCategory(
                merchantName: item.rawDescription,
                settings: settings,
                options: options
            )
        } catch {
            #if DEBUG
            print("🤖 [AI Category] ❌ error for '\(item.rawDescription)': \(error)")
            #endif
            return
        }

        #if DEBUG
        print("🤖 [AI Category] input : '\(item.rawDescription)'")
        print("🤖 [AI Category] result: merchant='\(result?.resolvedMerchantName ?? "-")' category='\(result?.categoryName ?? "-")' subcategory='\(result?.subcategoryName ?? "-")'")
        print("🤖 [AI Category] available categories: \(rootCategories.map(\.name).joined(separator: ", "))")
        #endif

        guard let result else { return }

        // Match the AI-returned category name against the user's actual category list.
        // Strategy (in order of priority):
        //   1. Exact match (case-insensitive, diacritics folded)
        //   2. One name contains the other  — e.g. AI says "Lazer", user has "Lazer e Entretenimento"
        //   3. Token overlap                — e.g. AI says "Entretenimento", user has "Lazer e Entretenimento"
        let fold: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        let aiCat = fold(result.categoryName)

        #if DEBUG
        print("🤖 [AI Category] matching '\(aiCat)' against list...")
        #endif

        guard !aiCat.isEmpty else {
            #if DEBUG
            print("🤖 [AI Category] ⚠️ AI returned empty category — leaving blank for user")
            #endif
            return
        }

        let matched = rootCategories.first { fold($0.name) == aiCat }
            ?? rootCategories.first { fold($0.name).contains(aiCat) || aiCat.contains(fold($0.name)) }
            ?? rootCategories.first { !merchantTokens(from: aiCat).intersection(merchantTokens(from: $0.name)).isEmpty }

        #if DEBUG
        if let matched {
            print("🤖 [AI Category] ✅ matched '\(result.categoryName)' → '\(matched.name)'")
        } else {
            print("🤖 [AI Category] ❌ no match found for '\(result.categoryName)' in [\(rootCategories.map(\.name).joined(separator: ", "))]")
        }
        #endif

        guard let matched else { return }

        let aiSub = result.subcategoryName.map(fold) ?? ""
        let sub = matched.subcategories.first { fold($0.name) == aiSub }
            ?? (aiSub.isEmpty ? nil : matched.subcategories.first {
                fold($0.name).contains(aiSub) || aiSub.contains(fold($0.name))
            })

        #if DEBUG
        print("🤖 [AI Category] subcategory: AI='\(result.subcategoryName ?? "-")' → matched='\(sub?.name ?? "none")'")
        #endif
        item.resolvedCategory     = matched
        item.resolvedSubcategory  = sub
        item.resolvedMerchantName = result.resolvedMerchantName

        // Propagate to other rows in the same import batch with the same merchant
        onCategoryResolved?(matched, sub, result.resolvedMerchantName)
    }
}

// MARK: - LinkTransactionSheet

struct LinkTransactionSheet: View {
    @Binding var item: ImportedTransaction
    let existingTransactions: [Transaction]
    let currencyCode: String

    @Environment(\.dismiss) private var dismiss
    @State private var searchText    = ""
    @State private var referenceDate = Date()   // tracks the month being displayed

    private let calendar = Calendar.current

    // When searching, ignore month filter and span all transactions.
    // Otherwise show only the selected month.
    private var filtered: [Transaction] {
        let base: [Transaction]
        if searchText.isEmpty {
            let comps = calendar.dateComponents([.year, .month], from: referenceDate)
            base = existingTransactions.filter {
                let c = calendar.dateComponents([.year, .month], from: $0.date)
                return c.year == comps.year && c.month == comps.month
            }
        } else {
            let q = searchText.lowercased()
            base = existingTransactions.filter {
                ($0.placeName?.lowercased().contains(q) ?? false)
                    || ($0.category?.name.lowercased().contains(q) ?? false)
                    || ($0.notes?.lowercased().contains(q) ?? false)
            }
        }
        return base.sorted { $0.date > $1.date }
    }

    private var monthTitle: String {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        df.locale = Locale.current
        return df.string(from: referenceDate).capitalized
    }

    private func stepMonth(by value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: referenceDate) {
            withAnimation(.easeInOut(duration: 0.2)) { referenceDate = next }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Month navigator (hidden while searching) ──
                if searchText.isEmpty {
                    HStack(spacing: 0) {
                        Button { stepMonth(by: -1) } label: {
                            Image(systemName: "chevron.left")
                                .font(.subheadline.bold())
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }

                        Spacer()

                        Text(monthTitle)
                            .font(.subheadline.bold())
                            .transition(.opacity)
                            .id(monthTitle)

                        Spacer()

                        Button { stepMonth(by: 1) } label: {
                            Image(systemName: "chevron.right")
                                .font(.subheadline.bold())
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .background(Color(.secondarySystemBackground))

                    Divider()
                }

                // ── Transaction list ──
                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text(searchText.isEmpty ? "Sem transações neste mês" : "Nenhum resultado")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered) { tx in
                        Button {
                            item.linkedTransactionId = tx.id
                            item.matchDecision       = .linkToExisting
                            item.isSelected          = true
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tx.category?.icon ?? "tag")
                                    .font(.subheadline)
                                    .foregroundStyle(Color(hex: tx.category?.color ?? "#8E8E93"))
                                    .frame(width: 34, height: 34)
                                    .background(Color(hex: tx.category?.color ?? "#8E8E93").opacity(0.12))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tx.placeName ?? tx.category?.name ?? "—")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary).lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(tx.date, format: .dateTime.day().month(.abbreviated).year())
                                            .font(.caption).foregroundStyle(.secondary)
                                        if let cat = tx.category {
                                            Text("· \(cat.name)")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(tx.amount.asCurrency(currencyCode))
                                        .font(.subheadline.bold())
                                    Image(systemName: tx.isPaid ? "checkmark.circle.fill" : "clock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(tx.isPaid ? .green : .orange)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .animation(.easeInOut(duration: 0.2), value: referenceDate)
                }
            }
            .navigationTitle(t("import.linkDrawerTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: t("common.search"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
            }
        }
    }
}

// CategoryPickerSheet is defined in Step4DetailsView.swift and shared across the app.

// MARK: - Merchant token helper (file-private, shared by row and parent view)

/// Splits a merchant name or raw bank description into a set of significant tokens
/// (4+ chars, lowercased, punctuation stripped) used for fuzzy merchant matching.
private func merchantTokens(from text: String) -> Set<String> {
    let normalized = text.lowercased()
        .replacingOccurrences(of: "[^a-z0-9áéíóúàèìòùâêîôûãõçñ ]",
                              with: " ",
                              options: .regularExpression)
    return Set(normalized.split(separator: " ").map(String.init).filter { $0.count >= 4 })
}
