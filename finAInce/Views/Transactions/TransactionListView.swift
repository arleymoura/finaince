import SwiftUI
import SwiftData
import UIKit
import Charts

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var goals: [Goal]
    @Query private var aiSettingsList: [AISettings]
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode
    @AppStorage("user.adultsCount") private var adultsCount = 0
    @AppStorage("user.childrenCount") private var childrenCount = 0
    
    // Conta padrão primeiro, depois o restante por ordem de criação
    private var sortedAccounts: [Account] {
        accounts.sorted { $0.isDefault && !$1.isDefault }
    }

    @State private var selectedMonth      = Calendar.current.component(.month, from: Date())
    @State private var selectedYear       = Calendar.current.component(.year,  from: Date())
    @State private var selectedAccountId: UUID? = nil   // nil = todas as contas
    @State private var selectedCategoryId: UUID? = nil
    @State private var selectedSubcategoryId: UUID? = nil
    @State private var selectedPaymentFilter: TransactionPaymentFilter = .all
    @State private var searchText         = ""
    @State private var isSearchVisible    = false
    @State private var showCategoryFilter = false
    @State private var viewMode: TransactionViewMode = .list
    @State private var chartInsight: String = ""
    @State private var isLoadingInsight: Bool = false
    @State private var lastInsightKey: String = ""
    @State private var showNewTransaction = false
    @State private var transactionToEdit: Transaction?   = nil
    @State private var txPendingDelete:   Transaction?   = nil
    @State private var showDeleteDialog                  = false
    @State private var showCSVImport                      = false   // single sheet — info + review
    @State private var didScrollToInitialDate             = false
    @State private var chatNavigationManager = ChatNavigationManager.shared
    @State private var showAnalysisEducation = false
    @State private var showMonthComparator = false
    @State private var analysisSharePayload: FinancialAnalysisSharePayload? = nil
    @State private var deepLinkManager = DeepLinkManager.shared
    @State private var isGeneratingAnalysis = false

    // MARK: - FTU
    @AppStorage("ftu.transactions.v1") private var hasSeenTransactionFTU = false
    @State private var showTransactionFTU      = false
    @State private var transactionFTUStepIndex = 0

    // MARK: - Performance cache
    @State private var cachedFiltered:    [Transaction] = []
    @State private var cachedGrouped:     [(date: Date, transactions: [Transaction])] = []
    @State private var cachedComparisons: [UUID: MonthlyRecurrenceComparison?] = [:]

    /// Drives the in-content ProgressView shown while the cache builds
    /// after the tab transition completes. Keeps the menu instant.
    @State private var isContentLoading: Bool = true


    // MARK: - Filtering

    private var selectedCategory: Category? {
        guard let selectedCategoryId else { return nil }
        return categories.first { $0.id == selectedCategoryId }
    }

    private var selectedSubcategory: Category? {
        guard let selectedSubcategoryId else { return nil }
        return categories.first { $0.id == selectedSubcategoryId }
    }

    private var categoryFilterTitle: String {
        if let selectedCategory, let selectedSubcategory {
            return "\(selectedCategory.displayName) / \(selectedSubcategory.displayName)"
        }

        if let selectedCategory {
            return selectedCategory.displayName
        }

        return t("transaction.category")
    }

    private var categoryFilterIcon: String {
        selectedSubcategory?.icon ?? selectedCategory?.icon ?? "tag.fill"
    }

    private var categoryFilterColor: String {
        selectedSubcategory?.color ?? selectedCategory?.color ?? "#8E8E93"
    }

    private var selectedAccount: Account? {
        guard let selectedAccountId else { return nil }
        return accounts.first { $0.id == selectedAccountId }
    }

    private var activeAISettings: AISettings? {
        aiSettingsList.first(where: { $0.isConfigured }) ?? aiSettingsList.first
    }

    private var currentMonthReference: MonthReference {
        MonthReference(year: selectedYear, month: selectedMonth)
    }

    private var previousMonthReference: MonthReference {
        if selectedMonth == 1 {
            return MonthReference(year: selectedYear - 1, month: 12)
        }
        return MonthReference(year: selectedYear, month: selectedMonth - 1)
    }

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    private let regularContentMaxWidth: CGFloat = 1100
    private var transactionCardCornerRadius: CGFloat { isRegularLayout ? 24 : 16 }
    private var transactionCardFillColor: Color {
        isRegularLayout ? FinAInceColor.elevatedSurface : FinAInceColor.primarySurface
    }
    private var heroGlassFill: Color { colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.14) }
    private var heroGlassStrongFill: Color { colorScheme == .dark ? .white.opacity(0.10) : .white.opacity(0.16) }
    private var heroGlassSoftFill: Color { colorScheme == .dark ? .white.opacity(0.07) : .white.opacity(0.12) }
    private var heroGlassBorder: Color { colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.10) }
    private var regularHeroTopColor: Color {
        colorScheme == .dark ? Color(red: 0.34, green: 0.25, blue: 0.72) : Color.accentColor.opacity(0.95)
    }
    private var regularHeroBottomColor: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.14, blue: 0.36) : Color.accentColor.opacity(0.65)
    }

    private var totalFilteredExpenses: Double {
        cachedFiltered
            .filter { $0.type == .expense }
            .reduce(0.0) { $0 + $1.amount }
    }

    private var paidTransactionsCount: Int {
        cachedFiltered.filter(\.isPaid).count
    }

    private var pendingTransactionsCount: Int {
        cachedFiltered.filter { !$0.isPaid }.count
    }

    private var hasActiveFilters: Bool {
        hasTransactionFilters || !searchText.isEmpty
    }

    private var hasTransactionFilters: Bool {
        selectedCategoryId != nil ||
        selectedSubcategoryId != nil ||
        selectedPaymentFilter != .all
    }

    // Thin aliases — actual data lives in @State cache updated by refreshListCache()
    var filteredTransactions: [Transaction] { cachedFiltered }
    var groupedByDay: [(date: Date, transactions: [Transaction])] { cachedGrouped }

    // MARK: - Cache refresh

    /// Recomputes filtered/grouped transactions and pre-builds the comparison dict.
    /// Call this whenever any filter input changes.
    private func refreshListCache() {
        let month   = selectedMonth
        let year    = selectedYear
        let search  = searchText.lowercased()

        let filtered = transactions.filter { tx in
            let c = Calendar.current.dateComponents([.month, .year], from: tx.date)
            guard c.month == month, c.year == year else { return false }

            if let id = selectedAccountId,     tx.account?.id    != id { return false }
            if let id = selectedCategoryId,    tx.category?.id   != id { return false }
            if let id = selectedSubcategoryId, tx.subcategory?.id != id { return false }

            switch selectedPaymentFilter {
            case .paid:    guard  tx.isPaid else { return false }
            case .pending: guard !tx.isPaid else { return false }
            case .all: break
            }

            if !search.isEmpty {
                let matchPlace    = tx.placeName?.lowercased().contains(search)  ?? false
                let matchNotes    = tx.notes?.lowercased().contains(search)       ?? false
                let matchCat      = tx.category.map { $0.name.lowercased().contains(search) || $0.displayName.lowercased().contains(search) } ?? false
                let matchSub      = tx.subcategory.map { $0.name.lowercased().contains(search) || $0.displayName.lowercased().contains(search) } ?? false
                let matchAccount  = tx.account?.name.lowercased().contains(search)     ?? false
                guard matchPlace || matchNotes || matchCat || matchSub || matchAccount else { return false }
            }
            return true
        }

        let cal      = Calendar.current
        let grouped  = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        let sorted   = grouped
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.0 > $1.0 }

        cachedFiltered = filtered
        cachedGrouped  = sorted

        // Pre-compute comparisons for every filtered row once — avoids O(n²) per render
        var comps: [UUID: MonthlyRecurrenceComparison?] = [:]
        for tx in filtered {
            comps[tx.id] = monthlyComparison(for: tx)
        }
        cachedComparisons = comps
    }

    private var monthTitle: String {
        var components = DateComponents()
        components.month = selectedMonth
        components.year = selectedYear
        components.day = 1

        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.effective.locale
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    WorkspaceBackground(isRegularLayout: isRegularLayout)
                        .ignoresSafeArea()

                    VStack(spacing: isRegularLayout ? 0 : -15) {
                        transactionHeader(topInset: proxy.safeAreaInsets.top)
                            .ignoresSafeArea(edges: .top)

                        VStack(spacing: 0) {
                            contentArea(for: proxy.size.height)
                        }
                        .padding(.top, isRegularLayout ? -30 : -44)
                    }
                }
                // FTU overlay — drawn on top of everything inside the GeometryReader
                .overlayPreferenceValue(TransactionFTUPreferenceKey.self) { targets in
                    GeometryReader { overlayProxy in
                        TransactionFTUOverlay(
                            isPresented: showTransactionFTU,
                            steps: transactionFTUSteps,
                            stepIndex: transactionFTUStepIndex,
                            targets: targets,
                            proxy: overlayProxy,
                            topInset: proxy.safeAreaInsets.top,
                            bottomInset: proxy.safeAreaInsets.bottom,
                            onNext: advanceTransactionFTU,
                            onClose: markTransactionFTUSeen
                        )
                    }
                    .ignoresSafeArea()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showNewTransaction) {
                NewTransactionFlowView()
            }
            .sheet(item: $transactionToEdit) { tx in
                TransactionEditView(transaction: tx)
            }
            // Único sheet: info → (push) review, tudo dentro do mesmo NavigationStack.
            .sheet(item: $analysisSharePayload) { payload in
                FinancialAnalysisShareSheet(payload: payload)
            }
            .sheet(isPresented: $showCategoryFilter) {
                TransactionCategoryFilterSheet(
                    selectedCategoryId: $selectedCategoryId,
                    selectedSubcategoryId: $selectedSubcategoryId
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAnalysisEducation) {
                NavigationStack {
                    FinancialAnalysisEducationDialog(
                        onCancel: {
                            showAnalysisEducation = false
                        },
                        onContinue: { analysisGoal in
                            isGeneratingAnalysis = true
                            showAnalysisEducation = false

                            DispatchQueue.main.async {
                                shareFinancialAnalysis(analysisGoal: analysisGoal)
                                isGeneratingAnalysis = false
                            }
                        }
                    )
                }
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationSizing(.page)
                .presentationBackground(.clear)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
            }
            .sheet(isPresented: $showMonthComparator) {
                MonthComparisonView(
                    transactions: transactions,
                    goals: goals,
                    currencyCode: currencyCode,
                    aiSettings: activeAISettings,
                    selectedAccountId: selectedAccountId,
                    initialMonthA: previousMonthReference,
                    initialMonthB: currentMonthReference
                )
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationSizing(.page)
            }
            .confirmationDialog(
                t("transaction.deleteRecTitle"),
                isPresented: $showDeleteDialog,
                titleVisibility: .visible
            ) {
                Button(t("transaction.deleteThis"), role: .destructive) {
                    if let tx = txPendingDelete { modelContext.delete(tx) }
                }
                Button(t("transaction.deleteThisNext"), role: .destructive) {
                    if let tx = txPendingDelete { deleteGroup(tx, scope: .thisAndFuture) }
                }
                Button(t("transaction.deleteAll"), role: .destructive) {
                    if let tx = txPendingDelete { deleteGroup(tx, scope: .all) }
                }
                Button(t("common.cancel"), role: .cancel) { txPendingDelete = nil }
            } message: {
                Text(t("transaction.deleteRecMsg"))
            }
            .animation(.spring(duration: 0.25), value: isSearchVisible)
            .onAppear {
                setDefaultAccount()
                showTransactionFTUIfNeeded()
                handleDeepLink(deepLinkManager.pendingDeepLink)
                // Show the in-content loader while the synchronous cache builds.
                // The 50ms sleep gives the tab transition time to finish and the
                // spinner time to appear BEFORE the heavy work blocks the main thread.
                Task { @MainActor in
                    isContentLoading = true
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    refreshListCache()
                    withAnimation(.easeOut(duration: 0.18)) {
                        isContentLoading = false
                    }
                }
            }
            // Immediate refresh on discrete filter changes
            .onChange(of: transactions)           { _, _ in refreshListCache() }
            .onChange(of: selectedMonth)          { _, _ in refreshListCache() }
            .onChange(of: selectedYear)           { _, _ in refreshListCache() }
            .onChange(of: selectedAccountId)      { _, _ in refreshListCache() }
            .onChange(of: selectedCategoryId)     { _, _ in refreshListCache() }
            .onChange(of: selectedSubcategoryId)  { _, _ in refreshListCache() }
            .onChange(of: selectedPaymentFilter)  { _, _ in refreshListCache() }
            .onChange(of: viewMode) { _, newMode in
                if newMode == .list { chartInsight = ""; lastInsightKey = "" }
            }
            .onChange(of: deepLinkManager.pendingDeepLink) { _, deepLink in
                handleDeepLink(deepLink)
            }
            .onChange(of: searchText) { _, _ in refreshListCache() }
            .overlay {
                if isGeneratingAnalysis {
                    ZStack {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()

                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)

                            Text(t("transaction.generatingAnalysis"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contentArea(for availableHeight: CGFloat) -> some View {
        if isRegularLayout {
            // Filter bar: full-screen-width background, content pinned to column width
            VStack(spacing: 0) {
                inlineFilterBar
                    .frame(maxWidth: regularContentMaxWidth)
                    .frame(maxWidth: .infinity)

                Divider()
            }
            .background {
                if isRegularLayout {
                    Color.clear
                } else {
                    WorkspaceBackground(isRegularLayout: isRegularLayout)
                }
            }

            if isContentLoading {
                contentLoadingView
            } else if filteredTransactions.isEmpty {
                ScrollView {
                    emptyState
                        .frame(maxWidth: regularContentMaxWidth)
                        .frame(maxWidth: .infinity, minHeight: availableHeight * 0.55)
                }
                .refreshable {
                    refreshListCache()
                }
            } else {
                transactionsWorkspaceView
            }
        } else {
            inlineFilterBar
                .background(WorkspaceBackground(isRegularLayout: isRegularLayout))

            Divider()

            if isContentLoading {
                contentLoadingView
            } else if filteredTransactions.isEmpty {
                ScrollView {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: availableHeight * 0.55)
                }
                .refreshable {
                    refreshListCache()
                }
            } else if viewMode == .charts {
                transactionChartsView
            } else {
                transactionList
                    .transactionFTUTarget(.transactions)
            }
        }
    }

    /// Centered ProgressView shown in the content area while the cache builds
    /// after a tab switch / cold launch. The header + filter bar stay visible.
    private var contentLoadingView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(t("common.loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspaceBackground(isRegularLayout: isRegularLayout))
    }

    // MARK: - Deep Links

    private func handleDeepLink(_ deepLink: DeepLink?) {
        switch deepLink {
        case let .transaction(id):
            guard let transaction = transactions.first(where: { matchesDeepLinkID(id, uuid: $0.id) }) else {
                deepLinkManager.routeToHome()
                return
            }

            let components = Calendar.current.dateComponents([.month, .year], from: transaction.date)
            selectedMonth = components.month ?? selectedMonth
            selectedYear = components.year ?? selectedYear
            transactionToEdit = transaction
            deepLinkManager.consume(.transaction(id: id))
        case let .transactionsCategory(id):
            guard let category = categories.first(where: { matchesDeepLinkID(id, uuid: $0.id) }) else {
                deepLinkManager.routeToHome()
                return
            }

            selectedCategoryId = category.id
            selectedSubcategoryId = nil
            selectedPaymentFilter = .all
            searchText = ""
            showCategoryFilter = false
            deepLinkManager.consume(.transactionsCategory(id: id))
        case .analysis:
            showAnalysisEducation = true
            deepLinkManager.consume(.analysis)
        default:
            return
        }
    }

    private func matchesDeepLinkID(_ id: String, uuid: UUID) -> Bool {
        uuid.uuidString.caseInsensitiveCompare(id) == .orderedSame
    }

    // MARK: - FTU helpers

    private var hasOnboardingTransactions: Bool {
        transactions.contains { $0.recurrenceType != .none }
    }

    private var transactionFTUSteps: [TransactionFTUStep] {
        var steps: [TransactionFTUStep] = []

        if hasOnboardingTransactions {
            steps.append(TransactionFTUStep(
                target:  .transactions,
                icon:    "arrow.trianglehead.2.clockwise.rotate.90",
                color:   Color.purple,
                title:   t("ftu.tx.recurringTitle"),
                message: t("ftu.tx.recurringBody")
            ))
        }

        steps.append(TransactionFTUStep(
            target:  .importButton,
            icon:    "square.and.arrow.down.on.square.fill",
            color:   Color.blue,
            title:   t("ftu.tx.importTitle"),
            message: t("ftu.tx.importBody")
        ))

        return steps
    }

    private func showTransactionFTUIfNeeded() {
        guard !hasSeenTransactionFTU else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard !hasSeenTransactionFTU, !transactionFTUSteps.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                transactionFTUStepIndex = 0
                showTransactionFTU = true
            }
        }
    }

    private func advanceTransactionFTU() {
        if transactionFTUStepIndex < transactionFTUSteps.count - 1 {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                transactionFTUStepIndex += 1
            }
        } else {
            markTransactionFTUSeen()
        }
    }

    private func markTransactionFTUSeen() {
        hasSeenTransactionFTU = true
        withAnimation(.easeInOut(duration: 0.3)) {
            showTransactionFTU = false
        }
    }
    

    // MARK: - Header

    private func transactionHeader(topInset: CGFloat) -> some View {
        Group {
            if isRegularLayout {
                regularTransactionHeader(topInset: topInset)
            } else {
                compactTransactionHeader(topInset: topInset)
            }
        }
        .sheet(isPresented: $showCSVImport) {
            CSVImportInfoView()
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationSizing(.page)
        }
    }

    private func compactTransactionHeader(topInset: CGFloat) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Text(t("transaction.title"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    showAnalysisEducation = true
                } label: {
                    Label(t("transaction.aiAnalysisButton"), systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(heroGlassFill)
                        .clipShape(Capsule())
                }
                .accessibilityLabel(t("transaction.aiAnalysisButton"))
                Button {
                    showCSVImport = true
                } label: {
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(heroGlassFill)
                        .clipShape(Circle())
                   
                }
                .help(t("csv.importButton"))
                .transactionFTUTarget(.importButton)
            }

            transactionMonthSelector

            filteredSummaryRow
        }
        .padding(.horizontal, 20)
        .padding(.top, topInset + 16)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [
                    regularHeroTopColor,
                    regularHeroBottomColor
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    bottomLeading: 24,
                    bottomTrailing: 24
                )
            )
        )
        .shadow(color: Color.accentColor.opacity(0.22), radius: 10, x: 0, y: 5)
    }

    private func regularTransactionHeader(topInset: CGFloat) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("transaction.title"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(t("transaction.heroMonthSummary", monthTitle.lowercased()))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                }

                Spacer(minLength: 16)

                HStack(spacing: 12) {
                    Button {
                        showAnalysisEducation = true
                    } label: {
                        Label(t("transaction.aiAnalysisButton"), systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(heroGlassFill)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("transaction.aiAnalysisButton"))

                    

                    Button {
                        showCSVImport = true
                    } label: {
                        Label(t("csv.importButton"), systemImage: "square.and.arrow.down.on.square.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(heroGlassFill)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(t("csv.importButton"))
                    .transactionFTUTarget(.importButton)
                    
                    
                    HStack(spacing: 12) {
                        monthNavigationButton(systemName: "chevron.left") {
                            moveMonth(by: -1)
                        }

                        Text(monthTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(heroGlassSoftFill)
                            .clipShape(Capsule())

                        monthNavigationButton(systemName: "chevron.right") {
                            moveMonth(by: 1)
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                transactionMetricCard(
                    title: t("transaction.title"),
                    value: totalFilteredExpenses.asCurrency(currencyCode),
                    icon: "eurosign.circle.fill",
                    tint: .white
                )
                transactionMetricCard(
                    title: t("transaction.paidPlural"),
                    value: "\(paidTransactionsCount)",
                    icon: "checkmark.circle.fill",
                    tint: Color.green.opacity(0.95)
                )
                transactionMetricCard(
                    title: t("transaction.pendingPlural"),
                    value: "\(pendingTransactionsCount)",
                    icon: "clock.fill",
                    tint: Color.orange.opacity(0.95)
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 16)
        .padding(.bottom, 24)
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.95),
                    Color.accentColor.opacity(0.65)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 28, bottomTrailing: 28))
        )
        .shadow(color: regularHeroBottomColor.opacity(colorScheme == .dark ? 0.28 : 0.20), radius: 14, x: 0, y: 8)
    }

    private func monthNavigationButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.bold())
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 38, height: 38)
                .background(heroGlassFill)
                .clipShape(Circle())
        }
    }

    private func transactionMetricCard(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(heroGlassStrongFill)
                    .frame(width: 46, height: 46)

                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(heroGlassSoftFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(heroGlassBorder, lineWidth: 1)
        )
    }

    private var transactionMonthSelector: some View {
        HStack(spacing: 12) {
            Button { moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 34, height: 34)
                    .background(heroGlassFill)
                    .clipShape(Circle())
            }

            Text(monthTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity)

            Button { moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 34, height: 34)
                    .background(heroGlassFill)
                    .clipShape(Circle())
            }
        }
    }

    private var viewModeToggle: some View {
        HStack(spacing: 0) {
            ForEach(TransactionViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(duration: 0.3)) { viewMode = mode }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(viewMode == mode ? 1 : 0.55))
                        .frame(width: 44, height: 30)
                        .background(
                            Capsule()
                                .fill(viewMode == mode
                                      ? heroGlassStrongFill
                                      : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(heroGlassSoftFill)
        .clipShape(Capsule())
    }

    private var filteredSummaryRow: some View {
        let count = cachedFiltered.count

        return HStack(alignment: .center, spacing: 0) {
            // Despesas
            VStack(alignment: .leading, spacing: 2) {
                Text(t("transaction.title"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                Text(totalFilteredExpenses.asCurrency(currencyCode))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            // Contagem
            VStack(alignment: .trailing, spacing: 2) {
                Text(count == 1 ? t("transaction.singular") : t("transaction.plural"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                Text("\(count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        }
        .overlay {
            if !isRegularLayout {
                viewModeToggle
            }
        }
        .animation(.easeInOut(duration: 0.2), value: count)
    }

    private func moveMonth(by delta: Int) {
        var components = DateComponents()
        components.month = selectedMonth + delta
        components.year = selectedYear

        if let date = Calendar.current.date(from: components) {
            let newComponents = Calendar.current.dateComponents([.month, .year], from: date)
            selectedMonth = newComponents.month ?? selectedMonth
            selectedYear = newComponents.year ?? selectedYear
        }
    }

    private func shareFinancialAnalysis(analysisGoal: String) {
        let analysisTransactions: [Transaction]
        let analysisAccounts: [Account]

        if let selectedAccountId {
            analysisTransactions = transactions.filter { $0.account?.id == selectedAccountId }
            analysisAccounts = accounts.filter { $0.id == selectedAccountId }
        } else {
            analysisTransactions = transactions
            analysisAccounts = accounts
        }

        let fullText = FinancialAnalysisExporter.buildAnalysisText(
            transactions: analysisTransactions,
            accounts: analysisAccounts,
            goals: goals,
            selectedMonth: selectedMonth,
            selectedYear: selectedYear,
            adults: adultsCount,
            children: childrenCount,
            currencyCode: currencyCode,
            analysisGoal: analysisGoal
        )
        UIPasteboard.general.string = fullText

        do {
            let fileURL = try FinancialAnalysisExporter.writeAnalysisFile(
                text: fullText,
                selectedMonth: selectedMonth,
                selectedYear: selectedYear
            )
            analysisSharePayload = FinancialAnalysisSharePayload(fileURL: fileURL)
        } catch {
            print("Failed to write financial analysis file: \(error)")
        }
    }

    // MARK: - Inline Filter Bar

    private var activeFiltersSummary: String {
        var parts: [String] = []
        if let acc = selectedAccount { parts.append(acc.name) }
        if selectedCategoryId != nil { parts.append(categoryFilterTitle) }
        if selectedPaymentFilter != .all { parts.append(selectedPaymentFilter.label) }
        if !searchText.isEmpty { parts.append("\"\(searchText)\"") }
        return parts.joined(separator: " · ")
    }

    private var inlineFilterBar: some View {
        VStack(spacing: 0) {
            if isRegularLayout {
                HStack(alignment: .center, spacing: 10) {
                    accountDropdown
                        .frame(maxWidth: .infinity)
                    
                    categoryDropdown
                        .frame(maxWidth: .infinity)
                    
                    statusDropdown
                        .frame(maxWidth: .infinity)
                    
                    searchField
                        .frame(maxWidth: .infinity)
                    
                    if hasActiveFilters {
                        Button {
                            withAnimation(.spring(duration: 0.25)) { clearFilters() }
                        } label: {
                            Text(t("common.clear"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .padding(.top, isRegularLayout ? 0 : 10)
            } else {
                HStack(alignment: .center,spacing: 8) {
                    accountDropdown
                        .frame(maxWidth: .infinity)
                    
                    categoryDropdown
                        .frame(maxWidth: .infinity)
                    
                    statusDropdown
                        .frame(maxWidth: .infinity)
                    
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            isSearchVisible.toggle()
                            if !isSearchVisible {
                                searchText = ""
                                isSearchFocused = false
                            }
                        }
                    } label: {
                        Image(systemName: isSearchVisible || !searchText.isEmpty
                              ? "magnifyingglass.circle.fill"
                              : "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSearchVisible || !searchText.isEmpty
                                         ? FinAInceColor.accentText : FinAInceColor.secondaryText)
                        .frame(width: 36, height: 36)
                        .background(FinAInceColor.secondarySurface)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, hasActiveFilters || isSearchVisible ? 6 : 10)
                
                if hasActiveFilters {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                        Text(activeFiltersSummary)
                            .font(.caption)
                            .foregroundStyle(FinAInceColor.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Button {
                            withAnimation(.spring(duration: 0.25)) { clearFilters() }
                        } label: {
                            Text(t("common.clear"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, isSearchVisible ? 4 : 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                if isSearchVisible {
                    searchField
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.25), value: hasActiveFilters)
    }

    private var accountDropdown: some View {
        Menu {
            Button {
                selectedAccountId = nil
            } label: {
                Label(t("account.allAccounts"), systemImage: "tray.2.fill")
            }
            Divider()
            ForEach(sortedAccounts) { account in
                Button {
                    selectedAccountId = account.id
                } label: {
                    Label(account.name, systemImage: account.icon)
                }
            }
        } label: {
            FilterPillView(
                label: selectedAccount?.name ?? t("transaction.account"),
                icon: selectedAccount?.icon ?? "tray.2.fill",
                color: selectedAccount?.color ?? "#8E8E93",
                isSelected: selectedAccountId != nil
            )
        }
    }

    private var categoryDropdown: some View {
        Button {
            showCategoryFilter = true
        } label: {
            FilterPillView(
                label: categoryFilterTitle,
                icon: categoryFilterIcon,
                color: categoryFilterColor,
                isSelected: selectedCategoryId != nil || selectedSubcategoryId != nil
            )
        }
        .buttonStyle(.plain)
    }

    private var statusDropdown: some View {
        Menu {
            ForEach(TransactionPaymentFilter.allCases, id: \.self) { filter in
                Button {
                    selectedPaymentFilter = filter
                } label: {
                    Label(filter.label, systemImage: filter.icon)
                }
            }
        } label: {
            FilterPillView(
                label: selectedPaymentFilter.label,
                icon: selectedPaymentFilter.icon,
                color: selectedPaymentFilter.color,
                isSelected: selectedPaymentFilter != .all
            )
        }
    }

    @FocusState private var isSearchFocused: Bool

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FinAInceColor.secondaryText)

            TextField(t("transaction.search"), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(t("common.done")) {
                            isSearchFocused = false
                        }
                        .fontWeight(.semibold)
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, isRegularLayout ? 8 : 10)
        .finInputFieldSurface(cornerRadius: 8)
        .shadow(color: FinAInceColor.borderSubtle, radius: 6, x: 0, y: 2)
    }

    private func clearFilters() {
        searchText = ""
        selectedCategoryId = nil
        selectedSubcategoryId = nil
        selectedPaymentFilter = .all
        withAnimation(.spring(duration: 0.25)) {
            isSearchVisible = false
        }
    }

    // MARK: - Charts

    private var insightKey: String {
        "\(selectedMonth)-\(selectedYear)-\(selectedAccountId?.uuidString ?? "all")"
    }

    private var cumulativeChartData: [CumulativePoint] {
        let currentMonthSeries = t("dashboard.currentMonthSeries")
        let previousMonthSeries = t("dashboard.previousMonthSeries")
        let cal = Calendar.current
        let today = Date()
        let isCurrentMonth = cal.component(.month, from: today) == selectedMonth
                          && cal.component(.year,  from: today) == selectedYear
        let todayDay = cal.component(.day, from: today)
        let maxDay   = isCurrentMonth ? todayDay : 31

        let prevMonth = selectedMonth == 1 ? 12 : selectedMonth - 1
        let prevYear  = selectedMonth == 1 ? selectedYear - 1 : selectedYear

        let currentExpenses = cachedFiltered.filter { $0.type == .expense }
        let prevExpenses = transactions.filter { tx in
            guard tx.type == .expense else { return false }
            let c = cal.dateComponents([.month, .year], from: tx.date)
            guard c.month == prevMonth, c.year == prevYear else { return false }
            if let id = selectedAccountId, tx.account?.id != id { return false }
            return true
        }

        func makeCumulative(_ txs: [Transaction], upTo: Int, series: String) -> [CumulativePoint] {
            let byDay = Dictionary(grouping: txs) { cal.component(.day, from: $0.date) }
            var running = 0.0
            return (1...max(1, upTo)).map { day in
                running += byDay[day]?.reduce(0.0) { $0 + $1.amount } ?? 0
                return CumulativePoint(id: "\(series)-\(day)", day: day,
                                       amount: running, series: series)
            }
        }

        return makeCumulative(currentExpenses, upTo: maxDay,  series: currentMonthSeries) +
               makeCumulative(prevExpenses,    upTo: maxDay,  series: previousMonthSeries)
    }

    private var cumulativeChartCard: some View {
        let data = cumulativeChartData
        let chartDayLabel = t("chart.day")
        let chartTotalLabel = t("dashboard.total")
        let chartSeriesLabel = t("chart.series")
        let currentMonthSeries = t("dashboard.currentMonthSeries")
        let previousMonthSeries = t("dashboard.previousMonthSeries")
        let currentPoints = data.filter { $0.series == currentMonthSeries }
        let prevPoints    = data.filter { $0.series == previousMonthSeries }
        let currentTotal  = currentPoints.last?.amount ?? 0
        let prevTotal     = prevPoints.last?.amount ?? 0
        let hasPrev       = prevTotal.isFinite && prevTotal > 0 && currentTotal.isFinite
        let rawPct        = hasPrev ? ((currentTotal - prevTotal) / prevTotal * 100).rounded() : 0
        let pct: Int      = rawPct.isFinite ? Int(rawPct) : 0
        let aiSettings = aiSettingsList.first

        return VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        
                        Image(systemName: "chart.xyaxis.line")
                            .font(.subheadline)
                            .foregroundStyle(.pink)
                        
                        Text(t("transaction.monthEvolution"))
                            .font(.headline)
                    }
                    
                    if hasPrev {
                        HStack(spacing: 4) {
                            Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2.weight(.bold))
                            Text(t("dashboard.vsPreviousMonthValue", "\(pct >= 0 ? "+" : "")\(pct)"))
                                .font(.caption)
                        }
                        .foregroundStyle(pct > 0 ? Color.red : Color.green)
                    }
                }
                Spacer()
                Text(currentTotal.asCurrency(currencyCode))
                    .foregroundStyle(FinAInceColor.primaryText)
                    .contentTransition(.numericText())
            }

            // Chart
            Chart(data) { point in
                AreaMark(
                    x: .value(chartDayLabel, point.day),
                    y: .value(chartTotalLabel, point.amount)
                )
                .foregroundStyle(by: .value(chartSeriesLabel, point.series))
                .opacity(0.12)

                LineMark(
                    x: .value(chartDayLabel, point.day),
                    y: .value(chartTotalLabel, point.amount)
                )
                .foregroundStyle(by: .value(chartSeriesLabel, point.series))
                .lineStyle(point.series == previousMonthSeries
                    ? StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    : StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale([
                currentMonthSeries:      Color.accentColor,
                previousMonthSeries:     Color.secondary.opacity(0.7)
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: 5)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    if let v = value.as(Double.self) {
                        AxisValueLabel {
                            Text(v.asCurrency(currencyCode))
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(height: 180)

            // AI Insight card
            if let settings = aiSettings, settings.isConfigured {
                Divider()
                insightCard(settings: settings)
            }
        }
        .padding(16)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            guard isRegularLayout else { return }
            showMonthComparator = true
        }
        .background(FinAInceColor.insetSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(FinAInceColor.borderSubtle, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .task(id: insightKey) {
            guard viewMode == .charts,
                  let settings = aiSettingsList.first,
                  settings.isConfigured,
                  insightKey != lastInsightKey else { return }
            lastInsightKey = insightKey
            await loadChartInsight(settings: settings)
        }
    }

    @ViewBuilder
    private func insightCard(settings: AISettings) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(settings.provider.accentColor)
                .frame(width: 28, height: 28)
                .background(settings.provider.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            if isLoadingInsight {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(t("transaction.analyzingData"))
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
                .padding(.top, 4)
            } else if !chartInsight.isEmpty {
                Text((try? AttributedString(markdown: chartInsight)) ?? AttributedString(chartInsight))
                    .font(.subheadline)
                    .foregroundStyle(FinAInceColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(t("transaction.notEnoughDataInsight"))
                    .font(.caption)
                    .foregroundStyle(FinAInceColor.secondaryText)
            }
        }
    }

    private func loadChartInsight(settings: AISettings) async {
        guard !isLoadingInsight else { return }
        let cal = Calendar.current
        let today = Date()
        let isCurrentMonth = cal.component(.month, from: today) == selectedMonth
                          && cal.component(.year,  from: today) == selectedYear
        let currentDay  = isCurrentMonth ? cal.component(.day, from: today) : 31
        let daysInMonth = cal.range(of: .day, in: .month,
                                    for: Calendar.current.date(from: DateComponents(
                                        year: selectedYear, month: selectedMonth))
                                    ?? today)?.count ?? 30

        let currentMonthSeries = t("dashboard.currentMonthSeries")
        let previousMonthSeries = t("dashboard.previousMonthSeries")
        let currentTotal = cumulativeChartData.filter { $0.series == currentMonthSeries }.last?.amount ?? 0
        let prevTotal    = cumulativeChartData.filter { $0.series == previousMonthSeries }.last?.amount ?? 0
        let topCategory  = categorySlices.first?.label
        let topMerchant  = merchantSlices.first?.label

        var monthComps = DateComponents()
        monthComps.year = selectedYear; monthComps.month = selectedMonth; monthComps.day = 1
        let monthDate   = cal.date(from: monthComps) ?? today
        let monthName   = monthDate.formatted(.dateTime.month(.wide).year()
                                             .locale(LanguageManager.shared.effective.locale))

        isLoadingInsight = true
        chartInsight = ""
        do {
            chartInsight = try await AIService.generateSpendingInsight(
                monthName:    monthName,
                currentDay:   currentDay,
                daysInMonth:  daysInMonth,
                currentTotal: currentTotal,
                prevTotal:    prevTotal,
                topCategory:  topCategory,
                topMerchant:  topMerchant,
                currencyCode: currencyCode,
                settings:     settings
            )
        } catch {
            chartInsight = ""
        }
        isLoadingInsight = false
    }

    private var categorySlices: [PieSliceData] {
        let expenses = cachedFiltered.filter { $0.type == .expense }
        guard !expenses.isEmpty else { return [] }
        let grouped = Dictionary(grouping: expenses) { $0.category?.id.uuidString ?? "none" }
        return grouped.map { _, txs in
            let cat = txs.first?.category
            return PieSliceData(
                id:     cat?.id.uuidString ?? "none",
                label:  cat?.name ?? t("insight.fallback.uncategorized"),
                amount: txs.reduce(0.0) { $0 + $1.amount },
                color:  Color(hex: cat?.color ?? "#8E8E93"),
                icon:   cat?.icon
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private var merchantSlices: [PieSliceData] {
        let expenses = cachedFiltered.filter { $0.type == .expense }
        guard !expenses.isEmpty else { return [] }
        let grouped = Dictionary(grouping: expenses) {
            $0.placeName?.trimmingCharacters(in: .whitespaces).isEmpty == false
                ? $0.placeName!
                : ($0.category?.displayName ?? t("insight.fallback.uncategorized"))
        }
        let palette: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo, .red]
        let all = grouped
            .map { name, txs in (name: name, amount: txs.reduce(0.0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
        let top  = Array(all.prefix(7))
        let rest = all.dropFirst(7)
        var slices: [PieSliceData] = top.enumerated().map { idx, item in
            PieSliceData(id: item.name, label: item.name, amount: item.amount,
                         color: palette[idx % palette.count], icon: nil)
        }
        if !rest.isEmpty {
            slices.append(PieSliceData(id: "outros", label: t("common.other"),
                                       amount: rest.reduce(0.0) { $0 + $1.amount },
                                       color: .gray, icon: nil))
        }
        return slices
    }

    private var transactionChartsView: some View {
        ScrollView {
            transactionChartsContent
            .padding(16)
        }
    }

    private var transactionChartsContent: some View {
        VStack(spacing: 16) {
            SpendingHistoryCard(transactions: transactions)
            PieChartCardView(title: t("transaction.byCategory"), slices: categorySlices, currencyCode: currencyCode)
            PieChartCardView(title: t("transaction.byMerchant"), slices: merchantSlices, currencyCode: currencyCode)
        }
    }

    private var transactionsWorkspaceView: some View {
        HStack(alignment: .top, spacing: 20) {
            transactionListCard
                .frame(minWidth: 0, maxWidth: .infinity)

            transactionsInsightsColumn
                .frame(width: 420)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .frame(maxWidth: regularContentMaxWidth)
        .frame(maxWidth: .infinity)
        .background(WorkspaceBackground(isRegularLayout: true))
    }

    private var transactionListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("transaction.title"))
                        .font(.headline.weight(.semibold))
                    Text("\(filteredTransactions.count) \(filteredTransactions.count == 1 ? t("transaction.singular") : t("transaction.plural"))")
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Divider()

            transactionList
                .transactionFTUTarget(.transactions)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .modifier(TransactionCardModifier(
            fillColor: transactionCardFillColor,
            cornerRadius: transactionCardCornerRadius,
            showsShadow: isRegularLayout
        ))
    }

    private var transactionsInsightsColumn: some View {
        ScrollView {
            VStack(spacing: 16) {
                cumulativeChartCard
                transactionChartsContent
            }
            .padding(20)
        }
        .modifier(TransactionCardModifier(
            fillColor: transactionCardFillColor,
            cornerRadius: transactionCardCornerRadius,
            showsShadow: isRegularLayout
        ))
    }

    // MARK: - List

    private var transactionList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(groupedByDay, id: \.date) { group in
                    Section(header: daySectionHeader(for: group)) {
                        ForEach(group.transactions) { transaction in
                            transactionRow(for: transaction)
                        }
                    }
                    .id(group.date)
                }
            }
            .modifier(TransactionListStyleModifier(isRegularLayout: isRegularLayout))
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollDismissesKeyboard(.immediately)
            .contentMargins(.bottom, isRegularLayout ? 0 : 96, for: .scrollContent)
            .refreshable {
                refreshListCache()
            }
            .onAppear {
                scrollToInitialDate(using: proxy)
            }
            .onChange(of: selectedMonth) { _, _ in
                scrollToSelectedPeriod(using: proxy)
            }
            .onChange(of: selectedYear) { _, _ in
                scrollToSelectedPeriod(using: proxy)
            }
            .modifier(TransactionListRegularStyling(isRegularLayout: isRegularLayout))
        }
    }

    private func daySectionHeader(for group: (date: Date, transactions: [Transaction])) -> some View {
        HStack {
            Text(sectionTitle(for: group.date))
            Spacer()
            Text(dayExpenseTotal(for: group.transactions).asCurrency(currencyCode))
        }
        .font(.subheadline)
        .foregroundStyle(FinAInceColor.secondaryText)
        .textCase(nil)
    }

    private func dayExpenseTotal(for transactions: [Transaction]) -> Double {
        transactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }

    private func transactionRow(for transaction: Transaction) -> some View {
        // Use pre-computed cache; fall back to live compute if not yet cached
        let comparison = cachedComparisons[transaction.id] ?? monthlyComparison(for: transaction)
        let badgeTapAction: (() -> Void)? = comparison.map { cmp in
            {
                let name      = transaction.placeName ?? transaction.category?.displayName ?? t("insight.fallback.recurringExpense")
                let amount    = transaction.amount.asCurrency(currencyCode)
                let prevTx    = previousMonthlyOccurrence(for: transaction)
                let prevAmt   = prevTx?.amount.asCurrency(currencyCode) ?? "desconhecido"
                let direction = cmp.direction == .increase ? "aumento" : "redução"
                let pct       = cmp.percentage
                chatNavigationManager.openChat(
                    prompt: """
                    A despesa recorrente "\(name)" teve um \(direction) de \(pct)% este mês \
                    (de \(prevAmt) para \(amount)). O que pode ter causado isso? Devo me \
                    preocupar? O que você recomenda?
                    """,
                    deepAnalysisFocus: "\(name) \(direction) \(pct)%",
                    shouldOfferDeepAnalysis: true,
                    startNewChat: true
                )
            }
        }

        return TransactionRowView(
            transaction:          transaction,
            showAccount:          selectedAccountId == nil,
            monthlyComparison:    comparison,
            onComparisonBadgeTap: badgeTapAction
        )
        .contentShape(Rectangle())
        .onTapGesture { transactionToEdit = transaction }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            paymentStatusButton(for: transaction)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            deleteButton(for: transaction)
        }
    }

    private func paymentStatusButton(for transaction: Transaction) -> some View {
        Button {
            transaction.isPaid.toggle()
        } label: {
            Image(systemName: transaction.isPaid ? "clock.arrow.circlepath" : "checkmark.circle.fill")
        }
        .tint(transaction.isPaid ? .orange : .green)
    }

    private func deleteButton(for transaction: Transaction) -> some View {
        Button(role: .destructive) {
            requestDelete(for: transaction)
        } label: {
            Image(systemName: "trash")
        }
    }

    private func monthlyComparison(for transaction: Transaction) -> MonthlyRecurrenceComparison? {
        guard transaction.type == .expense,
              transaction.recurrenceType == .monthly,
              transaction.amount > 0 else {
            return nil
        }

        guard let previousTransaction = previousMonthlyOccurrence(for: transaction),
              previousTransaction.amount.isFinite,
              previousTransaction.amount > 0 else {
            return nil
        }

        let difference = transaction.amount - previousTransaction.amount
        guard difference.isFinite, abs(difference) >= 0.01 else { return nil }

        let rawPercentage = (abs(difference) / previousTransaction.amount * 100).rounded()
        guard rawPercentage.isFinite else { return nil }

        let percentage = Int(rawPercentage)
        guard percentage > 0 else { return nil }

        return MonthlyRecurrenceComparison(
            percentage: percentage,
            direction: difference > 0 ? .increase : .decrease
        )
    }

    private func previousMonthlyOccurrence(for transaction: Transaction) -> Transaction? {
        // Only look back 60 days — avoids scanning the full transaction history
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: transaction.date) else { return nil }

        let comparableTransactions = transactions.filter { candidate in
            guard candidate.id != transaction.id,
                  candidate.type == .expense,
                  candidate.recurrenceType == .monthly,
                  candidate.date >= cutoff,
                  candidate.date < transaction.date else {
                return false
            }

            if let groupId = transaction.installmentGroupId {
                return candidate.installmentGroupId == groupId
            }

            return matchesRecurringMerchant(candidate, transaction)
        }

        return comparableTransactions.sorted { $0.date > $1.date }.first
    }

    private func matchesRecurringMerchant(_ candidate: Transaction, _ transaction: Transaction) -> Bool {
        if let place = normalizedRecurringText(transaction.placeName),
           let candidatePlace = normalizedRecurringText(candidate.placeName),
           place == candidatePlace {
            return true
        }

        guard let categoryId = transaction.category?.id,
              candidate.category?.id == categoryId else {
            return false
        }

        if let subcategoryId = transaction.subcategory?.id {
            return candidate.subcategory?.id == subcategoryId
        }

        return true
    }

    private func normalizedRecurringText(_ text: String?) -> String? {
        guard let normalized = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
              !normalized.isEmpty else {
            return nil
        }

        return normalized
    }

    private func requestDelete(for transaction: Transaction) {
        if transaction.recurrenceType == .monthly,
           transaction.installmentGroupId != nil {
            txPendingDelete = transaction
            showDeleteDialog = true
        } else {
            modelContext.delete(transaction)
        }
    }

    private func sectionTitle(for date: Date) -> String {
        date.formatted(
            .dateTime.day().month(.wide).locale(LanguageManager.shared.effective.locale)
        ).capitalized
    }

    private func scrollToInitialDate(using proxy: ScrollViewProxy) {
        guard !didScrollToInitialDate else { return }
        didScrollToInitialDate = true
        scrollToClosestDate(to: Date(), using: proxy, anchor: .center)
    }

    private func scrollToSelectedPeriod(using proxy: ScrollViewProxy) {
        let calendar = Calendar.current
        let todayComponents = calendar.dateComponents([.month, .year], from: Date())
        let selectedDate = todayComponents.month == selectedMonth && todayComponents.year == selectedYear
            ? Date()
            : calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1))

        guard let selectedDate else { return }
        scrollToClosestDate(to: selectedDate, using: proxy, anchor: .center)
    }

    private func scrollToClosestDate(to date: Date, using proxy: ScrollViewProxy, anchor: UnitPoint) {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        let closestDate = groupedByDay
            .map(\.date)
            .min { first, second in
                abs(first.timeIntervalSince(targetDay)) < abs(second.timeIntervalSince(targetDay))
            }

        guard let closestDate else { return }

        DispatchQueue.main.async {
            proxy.scrollTo(closestDate, anchor: anchor)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "list.bullet.rectangle" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if searchText.isEmpty {
                Button(t("transaction.add")) { showNewTransaction = true }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
    }

    private var emptyStateTitle: String {
        if !searchText.isEmpty {
            return t("transaction.noResult", searchText)
        }

        if hasActiveFilters {
            return t("transaction.noFilteredTransactions")
        }

        return t("transaction.empty")
    }

    // MARK: - Helpers

    private func deleteGroup(_ tx: Transaction, scope: RecurrenceEditScope) {
        guard let groupId = tx.installmentGroupId else {
            modelContext.delete(tx); return
        }
        let all = (try? modelContext.fetch(FetchDescriptor<Transaction>())) ?? []
        let related: [Transaction]
        switch scope {
        case .thisAndFuture:
            let idx = tx.installmentIndex ?? 0
            related = all.filter { $0.installmentGroupId == groupId && ($0.installmentIndex ?? 0) >= idx }
        case .all:
            related = all.filter { $0.installmentGroupId == groupId }
        case .thisOnly:
            related = [tx]
        }
        related.forEach { modelContext.delete($0) }
    }

    private func setDefaultAccount() {
        guard selectedAccountId == nil else { return }
        if let def = accounts.first(where: { $0.isDefault }) {
            selectedAccountId = def.id
        }
    }
}

// MARK: - Category Filter Sheet

private struct TransactionCategoryFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allCategories: [Category]

    @Binding private var selectedCategoryId: UUID?
    @Binding private var selectedSubcategoryId: UUID?

    @State private var draftCategoryId: UUID?
    @State private var draftSubcategoryId: UUID?
    @State private var expandedCategoryId: UUID?

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

    init(
        selectedCategoryId: Binding<UUID?>,
        selectedSubcategoryId: Binding<UUID?>
    ) {
        self._selectedCategoryId = selectedCategoryId
        self._selectedSubcategoryId = selectedSubcategoryId
        self._draftCategoryId = State(initialValue: selectedCategoryId.wrappedValue)
        self._draftSubcategoryId = State(initialValue: selectedSubcategoryId.wrappedValue)
        self._expandedCategoryId = State(initialValue: selectedCategoryId.wrappedValue)
    }

    private var rootCategories: [Category] {
        allCategories
            .filter { $0.parent == nil }
            .filter { $0.type == .expense || $0.type == .both }
            .sorted { first, second in
                if first.sortOrder == second.sortOrder {
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }
                return first.sortOrder < second.sortOrder
            }
    }

    private var expandedCategory: Category? {
        guard let expandedCategoryId else { return nil }
        return allCategories.first { $0.id == expandedCategoryId }
    }

    private var selectedCategory: Category? {
        guard let draftCategoryId else { return nil }
        return allCategories.first { $0.id == draftCategoryId }
    }

    private var selectedSubcategory: Category? {
        guard let draftSubcategoryId else { return nil }
        return allCategories.first { $0.id == draftSubcategoryId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(rootCategories) { category in
                            CategoryGridItem(
                                category: category,
                                isSelected: selectedCategory?.id == category.id
                            )
                            .onTapGesture {
                                withAnimation {
                                    draftCategoryId = category.id
                                    draftSubcategoryId = nil
                                    expandedCategoryId = category.id
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    if let expandedCategory {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t("transaction.subcategory"))
                                .font(.headline)
                                .padding(.horizontal)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach((expandedCategory.subcategories ?? []).sorted { $0.sortOrder < $1.sortOrder }) { subcategory in
                                    CategoryGridItem(
                                        category: subcategory,
                                        isSelected: selectedSubcategory?.id == subcategory.id,
                                        isSmall: true
                                    )
                                    .onTapGesture {
                                        withAnimation {
                                            draftSubcategoryId = subcategory.id
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut, value: expandedCategoryId)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(t("transaction.category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("common.clear")) {
                        withAnimation {
                            draftCategoryId = nil
                            draftSubcategoryId = nil
                            expandedCategoryId = nil
                        }
                    }
                    .disabled(draftCategoryId == nil && draftSubcategoryId == nil)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.ok")) {
                        selectedCategoryId = draftCategoryId
                        selectedSubcategoryId = draftSubcategoryId
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Account Pill

private struct AccountPillView: View {
    let label: String
    let icon: String
    let color: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.bold())
                Text(label)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color(hex: color) : FinAInceColor.secondarySurface)
            .foregroundStyle(isSelected ? FinAInceColor.inverseText : FinAInceColor.primaryText)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

private struct TransactionCardModifier: ViewModifier {
    let fillColor: Color
    let cornerRadius: CGFloat
    let showsShadow: Bool

    func body(content: Content) -> some View {
        content
            .background(fillColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(FinAInceColor.borderSubtle, lineWidth: 1)
            )
            .shadow(color: showsShadow ? Color.black.opacity(0.05) : .clear, radius: 16, x: 0, y: 10)
    }
}

private struct FilterPillView: View {
    let label: String
    let icon: String
    let color: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isSelected ? icon : icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color(hex: color) : FinAInceColor.secondaryText)

            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? FinAInceColor.primaryText : FinAInceColor.secondaryText)

            Image(systemName: isSelected ? "chevron.up.chevron.down" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isSelected ? Color(hex: color) : FinAInceColor.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            isSelected
                ? Color(hex: color).opacity(0.12)
                : FinAInceColor.secondarySurface
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    isSelected ? Color(hex: color).opacity(0.4) : FinAInceColor.borderSubtle,
                    lineWidth: 1
                )
        )
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

private enum TransactionPaymentFilter: CaseIterable {
    case all
    case paid
    case pending

    var label: String {
        switch self {
        case .all:
            return t("transaction.all")
        case .paid:
            return t("transaction.paidPlural")
        case .pending:
            return t("transaction.pendingPlural")
        }
    }

    var icon: String {
        switch self {
        case .all:
            return "line.3.horizontal.decrease.circle"
        case .paid:
            return "checkmark.circle.fill"
        case .pending:
            return "clock.fill"
        }
    }

    var color: String {
        switch self {
        case .all:
            return "#8E8E93"
        case .paid:
            return "#34C759"
        case .pending:
            return "#FF9500"
        }
    }
}

// MARK: - View Mode

private enum TransactionViewMode: CaseIterable {
    case list
    case charts

    var icon: String {
        switch self {
        case .list:   return "list.bullet"
        case .charts: return "chart.pie.fill"
        }
    }
}

// MARK: - Chart Data

private struct PieSliceData: Identifiable {
    let id:     String
    let label:  String
    let amount: Double
    let color:  Color
    let icon:   String?
}

private struct CumulativePoint: Identifiable {
    let id:     String
    let day:    Int
    let amount: Double
    let series: String
}

// MARK: - Pie Chart Card

private struct PieChartCardView: View {
    let title: String
    let slices: [PieSliceData]
    let currencyCode: String

    @State private var tappedSliceId: String? = nil
    @State private var chartSize: CGSize = .zero

    private var validSlices: [PieSliceData] {
        slices.filter { $0.amount.isFinite && $0.amount > 0 }
    }

    private var total: Double { validSlices.reduce(0.0) { $0 + $1.amount } }

    private var tappedSlice: PieSliceData? {
        guard let id = tappedSliceId else { return nil }
        return validSlices.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            HStack(spacing: 8) {
            
                Image(systemName: "chart.pie.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            
            
            
            if validSlices.isEmpty {
                Text(t("dashboard.noData"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                ZStack {
                    Chart(validSlices) { slice in
                        SectorMark(
                            angle:        .value("Valor", slice.amount),
                            innerRadius:  .ratio(0.55),
                            angularInset: 1.5
                        )
                        .cornerRadius(5)
                        .foregroundStyle(slice.color)
                        .opacity(tappedSliceId == nil || tappedSliceId == slice.id ? 1 : 0.35)
                    }
                    .chartLegend(.hidden)
                    .frame(height: 200)
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear          { chartSize = geo.size }
                            .onChange(of: geo.size) { _, s in chartSize = s }
                    })
                    .chartOverlay { _ in
                        GeometryReader { geo in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    handleTap(location: location, in: geo.size)
                                }
                        }
                    }

                    // Valor central do donut
                    VStack(spacing: 3) {
                        if let selected = tappedSlice {
                            Text(selected.label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(selected.amount.asCurrency(currencyCode))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                            Text(percentageText(for: selected))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(t("dashboard.total"))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(total.asCurrency(currencyCode))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(width: 96)
                    .multilineTextAlignment(.center)
                    .allowsHitTesting(false)

                    // Tooltip flutuante sobre a fatia selecionada
                    if let slice = tappedSlice {
                        sliceTooltip(slice)
                            .offset(tooltipOffset(for: slice.id))
                            .allowsHitTesting(false)
                            .transition(.scale(scale: 0.75).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: tappedSliceId)

                Divider()

                VStack(spacing: 10) {
                    ForEach(validSlices) { slice in
                        legendRow(slice)
                    }
                }
            }
        }
        .padding(16)
       // .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: Tooltip

    private func sliceTooltip(_ slice: PieSliceData) -> some View {
        VStack(spacing: 2) {
            Text(slice.amount.asCurrency(currencyCode))
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
            Text(percentageText(for: slice))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(slice.color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: slice.color.opacity(0.45), radius: 6, x: 0, y: 3)
    }

    /// Posiciona o tooltip na borda externa da fatia (raio 78% do círculo externo).
    private func tooltipOffset(for sliceId: String) -> CGSize {
        guard total > 0 else { return .zero }
        var startFraction = 0.0
        var sliceFraction = 0.0
        for s in slices {
            if s.id == sliceId { sliceFraction = s.amount / total; break }
            startFraction += s.amount / total
        }
        let midAngle = (startFraction + sliceFraction / 2) * 2 * .pi - .pi / 2
        let radius   = min(chartSize.width, chartSize.height) / 2 * 0.78
        return CGSize(width: cos(midAngle) * radius, height: sin(midAngle) * radius)
    }

    // MARK: Tap detection

    private func handleTap(location: CGPoint, in size: CGSize) {
        let center      = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx          = location.x - center.x
        let dy          = location.y - center.y
        let distance    = sqrt(dx * dx + dy * dy)
        let outerRadius = min(size.width, size.height) / 2
        let innerRadius = outerRadius * 0.55

        // Toque fora do anel → deseleciona
        guard distance >= innerRadius && distance <= outerRadius else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { tappedSliceId = nil }
            return
        }

        // Converte para ângulo normalizado 0…2π partindo de 12h em sentido horário
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }

        let target = (angle / (2 * .pi)) * total
        var cum    = 0.0
        for slice in validSlices {
            cum += slice.amount
            if target <= cum {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    tappedSliceId = tappedSliceId == slice.id ? nil : slice.id
                }
                return
            }
        }
    }

    // MARK: Legend row

    private func legendRow(_ slice: PieSliceData) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(slice.color)
                .frame(width: 10, height: 10)
            if let icon = slice.icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(slice.color)
            }
            Text(slice.label)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Text(slice.amount.asCurrency(currencyCode))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(percentageText(for: slice))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .opacity(tappedSliceId == nil || tappedSliceId == slice.id ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: tappedSliceId)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                tappedSliceId = tappedSliceId == slice.id ? nil : slice.id
            }
        }
    }

    private func percentageText(for slice: PieSliceData) -> String {
        guard total.isFinite, total > 0, slice.amount.isFinite else { return "0%" }
        let percentage = (slice.amount / total * 100).rounded()
        guard percentage.isFinite else { return "0%" }
        return "\(Int(percentage))%"
    }
}

private struct TransactionListRegularStyling: ViewModifier {
    let isRegularLayout: Bool

    func body(content: Content) -> some View {
        if isRegularLayout {
            content
                .listRowSpacing(8)
                .environment(\.defaultMinListRowHeight, 64)
        } else {
            content
        }
    }
}

private struct TransactionListStyleModifier: ViewModifier {
    let isRegularLayout: Bool

    func body(content: Content) -> some View {
        if isRegularLayout {
            content.listStyle(.plain)
        } else {
            content.listStyle(.insetGrouped)
        }
    }
}

struct MonthlyRecurrenceComparison {
    enum Direction {
        case increase
        case decrease
    }

    let percentage: Int
    let direction: Direction

    var icon: String {
        switch direction {
        case .increase:
            return "arrow.up"
        case .decrease:
            return "arrow.down"
        }
    }

    var color: Color {
        switch direction {
        case .increase:
            return .red
        case .decrease:
            return .green
        }
    }
}

// MARK: - Transaction Row

struct TransactionRowView: View {
    let transaction: Transaction
    var showAccount: Bool = false
    var monthlyComparison: MonthlyRecurrenceComparison? = nil
    /// Called when the user taps the price-change badge to ask the AI.
    var onComparisonBadgeTap: (() -> Void)? = nil
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    var body: some View {
        // Subcategoria tem prioridade sobre categoria para ícone e cor
        let iconSource = transaction.subcategory ?? transaction.category
        let iconColor = Color(hex: iconSource?.color ?? "#8E8E93")

        HStack(spacing: 12) {
            // Ícone da subcategoria (se houver) ou categoria
            Image(systemName: iconSource?.icon ?? "dollarsign.circle")
                .font(.subheadline)
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.15))
                .clipShape(Circle())

            // Conteúdo central
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let place = transaction.placeName, !place.isEmpty {
                        Text(place)
                            .foregroundStyle(.primary)
                    } else {
                        Text(transaction.category?.displayName ?? t("transaction.noPlace"))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

                HStack(spacing: 6) {
                    // Conta
                    if showAccount, let account = transaction.account {
                        HStack(spacing: 3) {
                            Image(systemName: account.icon)
                                .font(.system(size: 9))
                            Text(account.name)
                                .font(.caption2)
                        }
                        .foregroundStyle(Color(hex: account.color))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: account.color).opacity(0.12))
                        .clipShape(Capsule())
                    }

                    // Notas
                    if let notes = transaction.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Parcela
                    if transaction.recurrenceType == .installment,
                       let idx = transaction.installmentIndex,
                       let total = transaction.installmentTotal {
                        HStack(spacing: 3) {
                            Image(systemName: "square.stack.fill")
                                .font(.system(size: 9))
                            Text("\(idx)/\(total)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }

                    // Recorrente
                    if transaction.recurrenceType == .monthly || transaction.recurrenceType == .annual {
                        HStack(spacing: 3) {
                            Image(systemName: "repeat")
                                .font(.system(size: 12))
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 5) {
                    if let monthlyComparison {
                        if let action = onComparisonBadgeTap {
                            InsightPill(
                                icon:   monthlyComparison.icon,
                                label:  "\(monthlyComparison.percentage)%",
                                color:  monthlyComparison.color,
                                action: action
                            )
                        } else {
                            MonthlyRecurrenceComparisonBadge(comparison: monthlyComparison)
                        }
                    }

                    Text(transaction.amount.asCurrency(currencyCode))
                        .font(.subheadline.bold())
                        .foregroundStyle(transaction.type == .transfer ? Color.blue : Color.primary)
                }

                HStack(spacing: 3) {
                    Image(systemName: transaction.isPaid ? "checkmark.circle.fill" : "clock.fill")
                        .font(.system(size: 9))
                    Text(transaction.isPaid ? t("transaction.paid") : t("transaction.pending"))
                        .font(.caption2)
                }
                .foregroundStyle(transaction.isPaid ? Color.green : Color.orange)

                if !(transaction.receiptAttachments ?? []).isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 9, weight: .semibold))
                        if (transaction.receiptAttachments ?? []).count > 1 {
                            Text("\((transaction.receiptAttachments ?? []).count)")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct FinancialAnalysisSharePayload: Identifiable {
    let id = UUID()
    let fileURL: URL
}

private enum AnalysisGoalOption: CaseIterable, Identifiable {
    case cutSpending
    case planNextMonth
    case findOverspending

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .cutSpending:
            return t("transaction.aiAnalysisGoalCutSpending")
        case .planNextMonth:
            return t("transaction.aiAnalysisGoalPlanNextMonth")
        case .findOverspending:
            return t("transaction.aiAnalysisGoalFindOverspending")
        }
    }

    var icon: String {
        switch self {
        case .cutSpending:      return "scissors"
        case .planNextMonth:    return "calendar.badge.plus"
        case .findOverspending: return "magnifyingglass.circle.fill"
        }
    }
}

private struct FinancialAnalysisEducationDialog: View {
    let onCancel: () -> Void
    let onContinue: (String) -> Void
    @State private var selectedGoal = AnalysisGoalOption.cutSpending
    

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // Header
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.pie.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.18), lineWidth: 1)
                                    )
                            )

                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.92))

                        Image(systemName: "sparkles")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.18), lineWidth: 1)
                                    )
                            )
                    }

                    Text(t("transaction.aiAnalysisHowItWorksTitle"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(t("transaction.aiAnalysisSubtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.blue.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                // Content
                VStack(spacing: 20) {

                    VStack(alignment: .leading, spacing: 10) {
                        Text(t("transaction.aiAnalysisGoalQuestion"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                            spacing: 10
                        ) {
                            ForEach(AnalysisGoalOption.allCases) { goal in
                                Button {
                                    selectedGoal = goal
                                } label: {
                                    VStack(spacing: 8) {

                                        // Ícone
                                        Image(systemName: goal.icon)
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(
                                                selectedGoal == goal
                                                ? Color.accentColor
                                                : Color.secondary
                                            )

                                        // Texto
                                        Text(goal.localizedTitle)
                                            .font(.caption)
                                            .multilineTextAlignment(.center)
                                            .foregroundStyle(
                                                selectedGoal == goal
                                                ? Color.primary
                                                : Color.secondary
                                            )
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 90)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(
                                                selectedGoal == goal
                                                ? Color.accentColor.opacity(0.15)
                                                : FinAInceColor.secondarySurface
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                selectedGoal == goal
                                                ? Color.accentColor
                                                : Color.clear,
                                                lineWidth: 1.5
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        stepRow(number: 1, icon: "doc.text.fill",
                                text: t("transaction.aiAnalysisStep1"))
                        stepConnector
                        stepRow(number: 2, icon: "paperplane.fill",
                                text: t("transaction.aiAnalysisStep2"))
                        stepConnector
                        stepRow(number: 3, icon: "lightbulb.fill",
                                text: t("transaction.aiAnalysisStep3"))
                    }
                    .padding(.vertical, 4)

                    VStack(spacing: 8) {
                        Button {
                            onContinue(selectedGoal.localizedTitle)
                        } label: {
                            Text(t("transaction.aiAnalysisContinue"))
                                .font(FinAInceTypography.action)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(FinPrimaryButtonStyle())
                        Button(action: onCancel) {
                            Text(t("common.cancel"))
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(FinGhostButtonStyle())
                    }
                }
                .padding(20)
            }
        }
        .background(FinAInceColor.primarySurface)
    }

    // MARK: - Sub-views

    private func goalCard(_ goal: AnalysisGoalOption) -> some View {
        let isSelected = selectedGoal == goal
        return Button { withAnimation(.spring(duration: 0.2)) { selectedGoal = goal } } label: {
            HStack(spacing: 12) {
                Image(systemName: goal.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 30)

                Text(goal.localizedTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.08)
                          : FinAInceColor.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.35) : FinAInceColor.borderSubtle,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func stepRow(number: Int, icon: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var stepConnector: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 1.5, height: 10)
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
    }
}

private struct FinancialAnalysisShareSheet: UIViewControllerRepresentable {
    let payload: FinancialAnalysisSharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [payload.fileURL],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


private struct MonthlyRecurrenceComparisonBadge: View {
    let comparison: MonthlyRecurrenceComparison

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: comparison.icon)
                .font(.system(size: 8, weight: .semibold))
            Text("\(comparison.percentage)%")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(comparison.color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(comparison.color.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch comparison.direction {
        case .increase:
            return "\(comparison.percentage)% maior que o mês anterior"
        case .decrease:
            return "\(comparison.percentage)% menor que o mês anterior"
        }
    }
}

// MARK: - Transaction FTU infrastructure

private enum TransactionFTUTarget: String, Hashable {
    case transactions  // the transaction list area
    case importButton  // the CSV import icon in the header
}

private struct TransactionFTUStep: Identifiable {
    let id      = UUID()
    let target:  TransactionFTUTarget
    let icon:    String
    let color:   Color
    let title:   String
    let message: String
}

private struct TransactionFTUPreferenceKey: PreferenceKey {
    static var defaultValue: [TransactionFTUTarget: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [TransactionFTUTarget: Anchor<CGRect>],
        nextValue: () -> [TransactionFTUTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func transactionFTUTarget(_ target: TransactionFTUTarget) -> some View {
        anchorPreference(key: TransactionFTUPreferenceKey.self, value: .bounds) { anchor in
            [target: anchor]
        }
    }
}

// MARK: - Transaction FTU Overlay

private struct TransactionFTUOverlay: View {
    let isPresented: Bool
    let steps:       [TransactionFTUStep]
    let stepIndex:   Int
    let targets:     [TransactionFTUTarget: Anchor<CGRect>]
    let proxy:       GeometryProxy
    let topInset:    CGFloat
    let bottomInset: CGFloat
    let onNext:      () -> Void
    let onClose:     () -> Void

    private let highlightInset:  CGFloat = 10
    private let highlightRadius: CGFloat = 16

    var body: some View {
        if isPresented, steps.indices.contains(stepIndex) {
            let step = steps[stepIndex]

            let highlightRect: CGRect? = {
                guard let anchor = targets[step.target] else { return nil }
                return proxy[anchor].insetBy(dx: -highlightInset, dy: -highlightInset)
            }()

            ZStack {
                if let highlightRect {
                    // Dim with cutout
                    Canvas { ctx, size in
                        ctx.fill(
                            Path { p in
                                p.addRect(CGRect(origin: .zero, size: size))
                                p.addRoundedRect(
                                    in: highlightRect,
                                    cornerSize: CGSize(width: highlightRadius, height: highlightRadius)
                                )
                            },
                            with: .color(.black.opacity(0.58)),
                            style: FillStyle(eoFill: true)
                        )
                    }
                    .onTapGesture {}

                    FTUPulsingRing(
                        color:  step.color,
                        rect:   highlightRect,
                        radius: highlightRadius
                    )
                    .id(stepIndex)

                } else {
                    Color.black.opacity(0.58).onTapGesture {}
                }

                // Card placement:
                // • importButton → just below its highlight rect so the icon shows above
                // • transactions  → fixed just below the safe area (list is visible below card)
                let cardTop: CGFloat = {
                    if step.target == .importButton, let rect = highlightRect {
                        return rect.maxY + 16
                    }
                    return topInset + 8
                }()

                VStack {
                    FTUBottomCard(
                        icon:         step.icon,
                        color:        step.color,
                        title:        step.title,
                        message:      step.message,
                        currentIndex: stepIndex,
                        totalSteps:   steps.count,
                        isLastStep:   stepIndex == steps.count - 1,
                        onNext:       onNext,
                        onClose:      onClose
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, cardTop)
                    Spacer()
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.84), value: stepIndex)
        }
    }
}
#Preview {
    TransactionListView()
}
