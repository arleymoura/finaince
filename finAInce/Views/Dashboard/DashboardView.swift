import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var transactions: [Transaction]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var goals: [Goal]
    @Query private var costCenters: [CostCenter]
    @Query private var allCostCenterFiles: [CostCenterFile]
    @Query private var aiSettings: [AISettings]
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode
    @AppStorage("user.name") private var userName = ""
    @AppStorage("user.adultsCount") private var adultsCount = 0
    @AppStorage("user.childrenCount") private var childrenCount = 0

    
    @State private var selectedMonth      = Calendar.current.component(.month, from: Date())
    @State private var selectedYear       = Calendar.current.component(.year,  from: Date())
    @State private var selectedAccountId: UUID? = nil
    @State private var drilldownCategory: Category?
    @State private var showGoalForm    = false
    @State private var showNewProjectForm = false
    @State private var selectedProject: CostCenter? = nil
    @State private var showAISetup = false
    @State private var showCategoryDetails = false
    @State private var selectedCalendarDay: SelectedCalendarDay?
    @State private var transactionToEdit: Transaction?
    @State private var selectedInsightForAnalysis: Insight?
    @State private var insightAnalysisSharePayload: DashboardInsightAnalysisSharePayload?
    @State private var isGeneratingInsightAnalysis = false
    @State private var showMonthComparator = false
    @State private var deepLinkManager = DeepLinkManager.shared
    @State private var chatNavigationManager = ChatNavigationManager.shared
    @State private var helpTip: HelpTipItem? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isRegular: Bool { sizeClass == .regular }
    private var dashboardCardCornerRadius: CGFloat { isRegular ? 20 : 16 }
    private var dashboardCardFillColor: Color {
        isRegular ? FinAInceColor.elevatedSurface : FinAInceColor.secondarySurface
    }
    private var regularHeroTopColor: Color {
        colorScheme == .dark ? Color(red: 0.26, green: 0.19, blue: 0.58) : Color.accentColor.opacity(0.95)
    }
    private var regularHeroBottomColor: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.10, blue: 0.24) : Color.accentColor.opacity(0.68)
    }
    private var regularHeroGlassFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.12)
    }
    private var regularHeroGlassBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.12)
    }
    private var compactHeroTopColor: Color {
        colorScheme == .dark ? Color(red: 0.24, green: 0.18, blue: 0.54) : Color.accentColor.opacity(0.95)
    }
    private var compactHeroBottomColor: Color {
        colorScheme == .dark ? Color(red: 0.11, green: 0.09, blue: 0.22) : Color.accentColor.opacity(0.65)
    }
    private var compactHeroGlassFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.15)
    }
    private var compactHeroGlassSoftFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.20)
    }
    private var compactHeroGlassStrongFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.85)
    }

    /// On iPad inside NavigationSplitView, the GeometryReader proxy.safeAreaInsets.top
    /// is inflated by the NavigationStack's navigation bar area. Read the real
    /// window-level top inset directly from UIKit instead.
    private var windowTopInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.keyWindow?
            .safeAreaInsets.top ?? 54
    }
    // Empty-state missions
    @State private var showNewTransactionEmpty  = false
    @State private var showReceiptScannerEmpty  = false
    @State private var showCSVImportEmpty       = false

    // MARK: - Performance cache
    // Heavy derived data computed once and stored; updated via onChange / .task(id:)
    @State private var cachedMonthTx: [Transaction] = []
    @State private var cachedPendingAll: [Transaction] = []
    @State private var cachedPendingByDay: [Date: [Transaction]] = [:]
    @State private var cachedInsights: [Insight] = []
    @State private var isInsightsLoading: Bool = true
    @State private var insightsReloadToken = UUID()
    @State private var insightsSkeletonPhase: CGFloat = -1.0
    /// Drives the in-content ProgressView shown while the cache builds.
    /// Stays `true` until the FIRST refreshDashboardData() finishes after
    /// the tab transition completes — keeps the menu instant and parks
    /// the heavy work behind a clear loading state.
    @State private var isContentLoading: Bool = true

    private var cal: Calendar { Calendar.current }

    // MARK: - Derived (thin aliases over cache — O(1))

    var monthTransactions: [Transaction] { cachedMonthTx }

    var totalPaid: Double    { cachedMonthTx.filter {  $0.isPaid }.reduce(0) { $0 + $1.amount } }
    var totalPending: Double { cachedMonthTx.filter { !$0.isPaid }.reduce(0) { $0 + $1.amount } }

    var pendingTransactions: [Transaction] { cachedPendingAll }
    var activeGoals: [Goal]       { goals.filter { $0.isActive } }
    var activeProjects: [CostCenter] { costCenters.filter { $0.isActive } }
    var activeAISettings: AISettings? {
        aiSettings.first(where: isUsableAIConfiguration(_:))
        ?? aiSettings.first(where: { $0.isConfigured })
    }

    var isAIConfigured: Bool {
        guard let settings = activeAISettings else { return false }
        return isUsableAIConfiguration(settings)
    }

    var aiConfigurationSignature: String {
        aiSettings
            .map { "\($0.provider.rawValue)|\($0.model)|\($0.isConfigured)" }
            .joined(separator: ";")
    }

    private func isUsableAIConfiguration(_ settings: AISettings) -> Bool {
        guard settings.isConfigured else { return false }
        guard settings.provider.requiresAPIKey else { return true }
        let key = KeychainHelper.load(forKey: settings.provider.keychainKey) ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var monthPendingTransactions: [Transaction] {
        cachedPendingAll.filter {
            let c = cal.dateComponents([.month, .year], from: $0.date)
            return c.month == selectedMonth && c.year == selectedYear
        }
    }

    var upcomingPendingTransactions: [Transaction] {
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 3, to: start) else { return [] }
        return cachedPendingAll
            .filter { $0.date >= start && $0.date < end }
            .sorted { first, second in
                if cal.isDate(first.date, inSameDayAs: second.date) {
                    return first.amount > second.amount
                }
                return first.date < second.date
            }
    }

    /// Previsão = gastos já lançados no mês + valor restante de cada meta ativa.
    /// Fórmula: lançado + Σ max(0, meta.alvo − gasto_na_categoria_da_meta)
    var totalForecast: Double {
        let launched = totalPaid + totalPending

        let goalsRemaining = goals.reduce(0.0) { sum, goal in
            // Quanto já foi gasto na categoria desta meta no mês selecionado
            let spentOnGoal: Double
            if let cat = goal.category {
                spentOnGoal = monthTransactions
                    .filter {
                        let root = $0.category?.parent ?? $0.category
                        return root?.persistentModelID == cat.persistentModelID
                            || $0.category?.persistentModelID == cat.persistentModelID
                    }
                    .reduce(0) { $0 + $1.amount }
            } else {
                // Meta sem categoria específica cobre todo o gasto — sem valor restante a somar
                spentOnGoal = goal.targetAmount
            }
            return sum + max(0, goal.targetAmount - spentOnGoal)
        }

        return launched + goalsRemaining
    }

    var expensesByCategory: [(category: Category, total: Double)] {
        var dict: [Category: Double] = [:]
        for t in monthTransactions where t.type == .expense && t.amount > 0 {
            guard let cat = t.category else { continue }
            let root = cat.parent ?? cat
            dict[root, default: 0] += t.amount
        }
        return dict.map { ($0.key, $0.value) }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }

    /// Soma real dos gastos realizados no mês — usada no gráfico de categorias.
    /// Não inclui previsão de metas.
    var totalExpensesRealized: Double {
        expensesByCategory.reduce(0) { $0 + $1.total }
    }

    var monthTitle: String {
        var comps = DateComponents()
        comps.month = selectedMonth; comps.year = selectedYear; comps.day = 1
        let date = cal.date(from: comps) ?? Date()
        let fmt = DateFormatter()
        fmt.locale = LanguageManager.shared.effective.locale
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date).capitalized
    }

    var currentMonthReference: MonthReference {
        MonthReference(year: selectedYear, month: selectedMonth)
    }

    var previousMonthReference: MonthReference {
        let previousMonth = selectedMonth == 1 ? 12 : selectedMonth - 1
        let previousYear = selectedMonth == 1 ? selectedYear - 1 : selectedYear
        return MonthReference(year: previousYear, month: previousMonth)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    dashboardWorkspaceBackground
                        .ignoresSafeArea()

                    if isRegular {
                        // ── iPad: fixed header + scrollable content ──────────
                        // windowTopInset bypasses NavigationStack's inflated safe area value.
                        if !transactions.contains(where: { $0.amount > 0 }) {
                            ScrollView {
                                dashboardEmptyState(topInset: windowTopInset)
                            }
                            .ignoresSafeArea(edges: .top)
                            .refreshable { refreshDashboardData() }
                        } else {
                            VStack(spacing: 0) {
                                heroHeader(topInset: windowTopInset)
                                accountFilterBar
                                    .frame(maxWidth: 1100)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 12)
                                    .padding(.bottom, 4)
                                if isContentLoading {
                                    contentLoadingView
                                } else {
                                    ScrollView {
                                        iPadContentGrid
                                            .padding(.bottom, 32)
                                    }
                                    .refreshable { refreshDashboardData() }
                                }
                            }
                            .ignoresSafeArea(edges: .top)
                        }
                    } else {
                        // ── iPhone: fixed header + pinned filter bar + scrollable content ──
                        if !transactions.contains(where: { $0.amount > 0 }) {
                            ScrollView {
                                dashboardEmptyState(topInset: proxy.safeAreaInsets.top)
                            }
                            .ignoresSafeArea(edges: .top)
                            .refreshable { refreshDashboardData() }
                        } else {
                            VStack(spacing: -15) {
                                heroHeader(topInset: proxy.safeAreaInsets.top)
                                    .ignoresSafeArea(edges: .top)

                                VStack(spacing: 5) {
                                    accountFilterBar
                                        .background(dashboardWorkspaceBackground)

                                    Divider()

                                    if isContentLoading {
                                        contentLoadingView
                                    } else {
                                        ScrollView {
                                            iPhoneContentStack
                                                .padding(.bottom, 96)
                                        }
                                        .refreshable { refreshDashboardData() }
                                    }
                                }
                                .padding(.top, -44)
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            // Rebuild derived data when month, account filter, transactions, or AI setup changes.
            .task(id: "\(selectedMonth)/\(selectedYear)/\(selectedAccountId?.uuidString ?? "all")") {
                // Let the tab transition finish (and the spinner appear)
                // BEFORE the heavy synchronous refresh blocks the main thread.
                isContentLoading = true
                try? await Task.sleep(nanoseconds: 50_000_000)
                refreshDashboardData()
                withAnimation(.easeOut(duration: 0.18)) {
                    isContentLoading = false
                }
            }
            .onChange(of: transactions) { _, _ in
                refreshDashboardData()
            }
            .onChange(of: aiConfigurationSignature) { _, _ in
                refreshDashboardData()
            }
            .onChange(of: showAISetup) { _, isPresented in
                if !isPresented { refreshDashboardData() }
            }
            .onAppear {
                handleDeepLink(deepLinkManager.pendingDeepLink)
            }
            .sheet(isPresented: $showNewTransactionEmpty) {
                NewTransactionFlowView()
            }
            .sheet(isPresented: $showReceiptScannerEmpty) {
                NewTransactionFlowView(startWithScanner: true)
            }
            .sheet(isPresented: $showCSVImportEmpty) {
                CSVImportInfoView()
                    .presentationDetents([.fraction(0.82), .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
                    .presentationSizing(.page)
            }
            .onChange(of: deepLinkManager.pendingDeepLink) { _, deepLink in
                handleDeepLink(deepLink)
            }
            .sheet(item: $drilldownCategory) { category in
                CategoryDrilldownView(category: category, transactions: monthTransactions)
            }
            .sheet(isPresented: $showGoalForm) {
                GoalFormView()
                    .presentationDetents([.fraction(0.78), .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
                    .presentationSizing(.form)
            }
            .sheet(isPresented: $showNewProjectForm) {
                NavigationStack { ProjectFormView() }
                    .presentationDetents([.fraction(0.78), .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
                    .presentationSizing(.form)
            }
            .sheet(item: $selectedProject) { project in
                NavigationStack { ProjectDetailView(project: project) }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
                    .presentationSizing(.page)
            }
            .sheet(isPresented: $showAISetup) {
                NavigationStack {
                    AIProviderSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(t("common.close")) { showAISetup = false }
                                    .fontWeight(.semibold)
                            }
                        }
                }
            }
            .sheet(item: $selectedInsightForAnalysis) { selectedInsightForAnalysis in
                NavigationStack {
                    DashboardInsightAnalysisEducationDialog(
                        insight: selectedInsightForAnalysis,
                        onCancel: {
                            self.selectedInsightForAnalysis = nil
                        },
                        onContinue: {
                            let insightToShare = selectedInsightForAnalysis
                            isGeneratingInsightAnalysis = true
                            self.selectedInsightForAnalysis = nil

                            DispatchQueue.main.async {
                                shareInsightAnalysis(insightToShare)
                                isGeneratingInsightAnalysis = false
                            }
                        }
                    )
                }
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
                .presentationBackground(.clear)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
            }
            .sheet(item: $insightAnalysisSharePayload) { payload in
                DashboardInsightAnalysisShareSheet(payload: payload)
            }
            .sheet(item: $transactionToEdit) { transaction in
                TransactionEditView(transaction: transaction)
            }
            .sheet(item: $selectedCalendarDay) { selectedDay in
                PendingDayTransactionsSheet(
                    date: selectedDay.date,
                    transactions: pendingTransactions(for: selectedDay.date)
                )
            }
            .sheet(isPresented: $showCategoryDetails) {
                CategoryDetailsSheet(
                    expensesByCategory: expensesByCategory,
                    total: totalExpensesRealized,
                    transactions: monthTransactions
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(FinAInceColor.primarySurface)
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
            .overlay {
                if isGeneratingInsightAnalysis {
                    ZStack {
                        FinAInceColor.primaryText.opacity(0.18)
                            .ignoresSafeArea()

                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)

                            Text(t("dashboard.generatingInsightAnalysis"))
                                .font(.subheadline)
                                .foregroundStyle(FinAInceColor.secondaryText)
                        }
                        .padding(20)
                        .finElevatedSurface(cornerRadius: 16)
                    }
                }
            }
            .helpTipOverlay(item: $helpTip)
        }
    }

    // MARK: - Empty State (no transactions yet)

    /// Centered ProgressView shown in the content area while the cache builds
    /// after a tab switch / cold launch. The header stays visible above it.
    private var contentLoadingView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(t("common.loading"))
                .font(.subheadline)
                .foregroundStyle(FinAInceColor.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dashboardWorkspaceBackground)
    }

    private func dashboardEmptyState(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {

            // ── Mini header strip ─────────────────────────────────────────
//            HStack(spacing: 12) {
//                Button { moveMonth(by: -1) } label: {
//                    Image(systemName: "chevron.left")
//                        .font(.subheadline.bold())
//                        .foregroundStyle(.white.opacity(0.9))
//                        .frame(width: 34, height: 34)
//                        .background(.white.opacity(0.15))
//                        .clipShape(Circle())
//                }
//                Text(monthTitle)
//                    .font(.subheadline.weight(.semibold))
//                    .foregroundStyle(.white.opacity(0.9))
//                    .frame(maxWidth: .infinity)
//                Button { moveMonth(by: 1) } label: {
//                    Image(systemName: "chevron.right")
//                        .font(.subheadline.bold())
//                        .foregroundStyle(.white.opacity(0.9))
//                        .frame(width: 34, height: 34)
//                        .background(.white.opacity(0.15))
//                        .clipShape(Circle())
//                }
//            }
//            .padding(.horizontal, 20)
//            .padding(.top, topInset + 16)
//            .padding(.bottom, 20)
//            .background(
//                LinearGradient(
//                    colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.65)],
//                    startPoint: .topLeading, endPoint: .bottomTrailing
//                )
//            )
//            .clipShape(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 24, bottomTrailing: 24)))
//            .shadow(color: Color.accentColor.opacity(0.24), radius: 12, x: 0, y: 6)

            // ── Headline ──────────────────────────────────────────────────
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 68, height: 68)
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.top, 32)

                Text(t("dashboard.emptyReadyTitle"))
                    .font(.title2.bold())
                    .foregroundStyle(FinAInceColor.primaryText)

                Text(t("dashboard.emptyReadyDesc"))
                    .font(.subheadline)
                    .foregroundStyle(FinAInceColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.bottom, 28)
            .padding(.top, 28)

            // ── Missions ──────────────────────────────────────────────────
            VStack(spacing: 12) {
                bankImportMissionCard
                emptyMissionCard(
                    icon: "plus.circle.fill",
                    iconColor: Color.accentColor,
                    title: t("dashboard.manualEntryTitle"),
                    desc: t("dashboard.manualEntryDesc"),
                    badge: nil
                ) { showNewTransactionEmpty = true }

                emptyMissionCard(
                    icon: "camera.viewfinder",
                    iconColor: Color.purple,
                    title: t("dashboard.scanReceiptTitle"),
                    desc: t("dashboard.scanReceiptDesc"),
                    badge: nil
                ) { showReceiptScannerEmpty = true }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // ── Card grande: importar do banco ─────────────────────────────────────

    private var bankImportMissionCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header do card
            HStack(spacing: 14) {
                Image(systemName: "building.columns.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(t("dashboard.importBankTitle"))
                            .font(.subheadline.weight(.semibold))
                        Text(t("dashboard.recommended"))
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(t("dashboard.importBankDesc"))
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Divider().padding(.horizontal, 16)

            // Mini tutorial de como exportar
            VStack(alignment: .leading, spacing: 10) {
                Text(t("dashboard.howTo"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FinAInceColor.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.4)

                HStack(spacing: 0) {
                    bankStep(icon: "iphone", label: "App\ndo banco")
                    bankArrow
                    bankStep(icon: "list.bullet.rectangle", label: "Extrato /\nHistórico")
                    bankArrow
                    bankStep(icon: "square.and.arrow.up", label: "Exportar /\nCompartilhar")
                    bankArrow
                    bankStep(icon: "arrow.down.circle.fill", label: "Abrir no\nfinAInce", accent: true)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().padding(.horizontal, 16)

            // CTA
            Button {
                showCSVImportEmpty = true
            } label: {
                HStack {
                    Text(t("dashboard.importNow"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .finElevatedSurface(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.green.opacity(0.22), lineWidth: 1.25)
        )
    }

    private func bankStep(icon: String, label: String, accent: Bool = false) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent ? Color.accentColor : .secondary)
                .frame(width: 36, height: 36)
                .background((accent ? Color.accentColor : Color(.systemGray5)).opacity(accent ? 0.12 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            Text(label)
                .font(.caption2)
                .foregroundStyle(accent ? Color.accentColor : .secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var bankArrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color(.systemGray4))
            .padding(.bottom, 14)   // alinha visualmente com os ícones
    }

    // ── Card simples: missão genérica ───────────────────────────────────────

    private func emptyMissionCard(
        icon: String,
        iconColor: Color,
        title: String,
        desc: String,
        badge: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(iconColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FinAInceColor.primaryText)
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FinAInceColor.secondaryText)
            }
            .padding(16)
            .finElevatedSurface(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Deep Links

    private func handleDeepLink(_ deepLink: DeepLink?) {
        switch deepLink {
        case let .category(id):
            guard let category = categories.first(where: { matchesDeepLinkID(id, uuid: $0.id) }) else {
                deepLinkManager.routeToHome()
                return
            }

            drilldownCategory = category
            deepLinkManager.consume(.category(id: id))
        case let .project(id):
            guard let project = costCenters.first(where: { matchesDeepLinkID(id, uuid: $0.id) }) else {
                deepLinkManager.routeToHome()
                return
            }

            selectedProject = project
            deepLinkManager.consume(.project(id: id))
        case .monthComparison:
            showMonthComparator = true
            deepLinkManager.consume(.monthComparison)
        default:
            return
        }
    }

    private func matchesDeepLinkID(_ id: String, uuid: UUID) -> Bool {
        uuid.uuidString.caseInsensitiveCompare(id) == .orderedSame
    }



    // MARK: - Insights

    @ViewBuilder
    private var insightsSection: some View {
        ZStack {
            if !cachedInsights.isEmpty {
                InsightCarousel(
                    insights: cachedInsights,
                    badgeTitle: t("dashboard.quickAnalysisTitle"),
                    ctaTitle: t(isAIConfigured ? "dashboard.viewMoreDetails" : "dashboard.viewWithAI")
                ) { insight in
                    handleInsightTap(insight)
                }
                .opacity(isInsightsLoading ? 0 : 1)
            }

            if isInsightsLoading {
                insightsSkeletonCard
                    .transition(.opacity)
            }
        }
        .frame(height: 166)
        .animation(.easeInOut(duration: 0.22), value: isInsightsLoading)
    }

    private var insightsSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("IA") //localizar
                        .font(.caption2.bold())
                        .foregroundStyle(Color.accentColor)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(t("dashboard.insightsLoadingTitle"))
                        .font(.subheadline.bold())
                        .foregroundStyle(FinAInceColor.primaryText)

                    Text(t("dashboard.insightsLoadingSubtitle"))
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }

                Spacer()

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 10, height: 10)
            }

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(height: 11)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(height: 11)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 210, height: 11)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: 140, alignment: .topLeading)
        .background(Color.accentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: isRegular ? 20 : 16))
        .overlay(
            RoundedRectangle(cornerRadius: isRegular ? 20 : 16)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 1)
        )
        .overlay {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 120)
                .rotationEffect(.degrees(14))
                .offset(x: proxy.size.width * insightsSkeletonPhase)
                .blendMode(.plusLighter)
            }
            .clipShape(RoundedRectangle(cornerRadius: isRegular ? 20 : 16))
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
        .onAppear {
            insightsSkeletonPhase = -0.45
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                insightsSkeletonPhase = 1.25
            }
        }
    }

    private func handleInsightTap(_ insight: Insight) {
        if isAIConfigured {
            chatNavigationManager.openChat(
                prompt: insight.chatPrompt,
                deepAnalysisFocus: insight.title,
                shouldOfferDeepAnalysis: true,
                startNewChat: true
            )
        } else {
            selectedInsightForAnalysis = insight
        }
    }

    private func shareInsightAnalysis(_ insight: Insight) {
        let analysisTransactions: [Transaction]
        let analysisAccounts: [Account]

        if let selectedAccountId {
            analysisTransactions = transactions.filter { $0.account?.id == selectedAccountId }
            analysisAccounts = accounts.filter { $0.id == selectedAccountId }
        } else {
            analysisTransactions = transactions
            analysisAccounts = accounts
        }

        let analysisGoal = t("dashboard.insightAnalysisGoalTemplate", insight.title, insight.body)
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
            insightAnalysisSharePayload = DashboardInsightAnalysisSharePayload(fileURL: fileURL)
        } catch {
            print("Failed to write insight analysis file: \(error)")
        }
    }

    @ViewBuilder
    private var aiSetupCard: some View {
        if !isAIConfigured {
            Button {
                showAISetup = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.18), Color.blue.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)

                        Image(systemName: "brain.head.profile")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("dashboard.aiSetupTitle"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FinAInceColor.primaryText)

                        Text(t("dashboard.aiSetupDesc"))
                            .font(.caption)
                            .foregroundStyle(FinAInceColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(t("dashboard.aiSetupButton"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(14)
                .finElevatedSurface(cornerRadius: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor.opacity(0.14), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Hero Header

    private func heroHeader(topInset: CGFloat) -> some View {
        if isRegular {
            return AnyView(iPadHeroHeader(topInset: topInset))
        }

        return AnyView(compactHeroHeader(topInset: topInset))
    }

    private func compactHeroHeader(topInset: CGFloat) -> some View {
        // Content VStack is the size anchor — gradient is a .background so it
        // never inflates layout height (avoids the ZStack expansion bug on iPad).
        // The parent container (.ignoresSafeArea(edges:.top)) already places this
        // view at y=0 so the gradient bleeds behind the status bar naturally.
        VStack(spacing: 0) {

            // Month navigator
            HStack(spacing: 12) {
                Button { moveMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 34, height: 34)
                        .background(compactHeroGlassFill)
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
                        .background(compactHeroGlassFill)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, topInset + 16)

            // Main amount — gasto até agora
            Button {
                helpTip = HelpTipItem(
                    icon: "creditcard.fill",
                    color: Color.accentColor,
                    title: t("dashboard.help.spentTitle"),
                    body:  t("dashboard.help.spentBody")
                )
            } label: {
                VStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Text(t("dashboard.spent"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Text(totalPaid.asCurrency(currencyCode))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 20)

            // Previsto / Pendente
            HStack(spacing: 0) {
                heroStatItem(
                    label: t("dashboard.forecast"),
                    amount: totalForecast,
                    icon: "calendar.badge.clock",
                    onHelp: {
                        helpTip = HelpTipItem(
                            icon: "calendar.badge.clock",
                            color: Color.orange,
                            title: t("dashboard.help.forecastTitle"),
                            body:  t("dashboard.help.forecastBody")
                        )
                    }
                )
                Rectangle()
                    .fill(compactHeroGlassSoftFill)
                    .frame(width: 1, height: 44)
                heroStatItem(
                    label: t("dashboard.pending"),
                    amount: totalPending,
                    icon: "clock.fill",
                    onHelp: {
                        helpTip = HelpTipItem(
                            icon: "clock.fill",
                            color: Color.purple,
                            title: t("dashboard.help.pendingTitle"),
                            body:  t("dashboard.help.pendingBody")
                        )
                    }
                )
            }
            .padding(.bottom, totalForecast > 0 ? 0 : 16)

            if totalForecast > 0 {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(compactHeroGlassSoftFill)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(compactHeroGlassStrongFill)
                                .frame(
                                    width: geo.size.width * min(totalPaid / totalForecast, 1.0),
                                    height: 6
                                )
                                .animation(.easeOut(duration: 0.5), value: totalPaid)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(t("dashboard.percentDoneValue", Int(totalPaid / totalForecast * 100)))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text("\(t("dashboard.prevPrefix"))\(totalForecast.asCurrency(currencyCode))")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            } else {
                Spacer().frame(height: 4)
            }
        }
        // Cap width on iPad so text doesn't spread too wide; full-bleed via frame below.
        .frame(maxWidth: isRegular ? 700 : .infinity)
        .frame(maxWidth: .infinity)
        // Gradient as background — never affects layout height.
        .background {
            LinearGradient(
                colors: [compactHeroTopColor, compactHeroBottomColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 24, bottomTrailing: 24))
        )
        .shadow(color: compactHeroBottomColor.opacity(colorScheme == .dark ? 0.30 : 0.24), radius: 12, x: 0, y: 6)
    }

    private func iPadHeroHeader(topInset: CGFloat) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(userName.isEmpty ? t("dashboard.title") : "Ola, \(userName)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(t("dashboard.heroMonthSummary", monthTitle.lowercased()))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                }

                Spacer(minLength: 16)

                HStack(spacing: 12) {


                    Button {
                        showMonthComparator = true
                    } label: {
                        Label(t("dashboard.compareMonthButton"), systemImage: "chart.line.text.clipboard")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(regularHeroGlassFill)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("dashboard.compareMonthButton"))

                    monthNavigationButton(systemName: "chevron.left") {
                        moveMonth(by: -1)
                    }
                    
                    Text(monthTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(regularHeroGlassFill)
                        .clipShape(Capsule())

                    monthNavigationButton(systemName: "chevron.right") {
                        moveMonth(by: 1)
                    }
                }
            }

            HStack(spacing: 14) {
                heroMetricCard(
                    title: t("dashboard.spent"),
                    value: totalPaid.asCurrency(currencyCode),
                    icon: "creditcard.fill",
                    tint: .white
                )
                heroMetricCard(
                    title: t("dashboard.forecast"),
                    value: totalForecast.asCurrency(currencyCode),
                    icon: "calendar.badge.clock",
                    tint: Color.orange.opacity(0.95)
                )
                heroMetricCard(
                    title: t("dashboard.pending"),
                    value: totalPending.asCurrency(currencyCode),
                    icon: "clock.fill",
                    tint: Color.purple.opacity(0.95)
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 16)
        .padding(.bottom, 24)
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [regularHeroTopColor, regularHeroBottomColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 28, bottomTrailing: 28))
        )
        .shadow(color: regularHeroBottomColor.opacity(colorScheme == .dark ? 0.28 : 0.20), radius: 14, x: 0, y: 8)
    }

    private func monthNavigationButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.bold())
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 38, height: 38)
                .background(regularHeroGlassFill)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func heroMetricCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .textCase(.uppercase)
                    .tracking(0.7)
            }

            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(regularHeroGlassFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(regularHeroGlassBorder, lineWidth: 1)
        )
    }

    private func heroStatItem(
        label: String,
        amount: Double,
        icon: String,
        onHelp: (() -> Void)? = nil
    ) -> some View {
        Button {
            onHelp?()
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                    if onHelp != nil {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Text(amount.asCurrency(currencyCode))
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(onHelp == nil)
    }

    // MARK: - Account Filter Bar

    private var accountFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                accountPill(nil, label: "Todas", color: nil)
                ForEach(accounts) { account in
                    accountPill(account.id, label: account.name, color: account.color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isRegular ? FinAInceColor.elevatedSurface : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isRegular ? FinAInceColor.borderSubtle : Color.clear, lineWidth: 1)
        )
        .shadow(color: isRegular ? Color.black.opacity(0.05) : .clear, radius: 14, y: 8)
        .padding(.horizontal, isRegular ? 24 : 0)
    }

    private func accountPill(_ id: UUID?, label: String, color: String?) -> some View {
        let isSelected = selectedAccountId == id
        return Button {
            selectedAccountId = (id == nil) ? nil : (isSelected ? nil : id)
        } label: {
            HStack(spacing: 5) {
                if let color {
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                isSelected ? FinAInceColor.primaryActionBackground : FinAInceColor.secondarySurface
            )
            .foregroundStyle(isSelected ? FinAInceColor.primaryActionForeground : FinAInceColor.primaryText)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.clear : FinAInceColor.borderStrong,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calendar

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            monthPendingCalendar
            upcomingExpensesSection
        }
    }

    private var upcomingExpensesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if upcomingPendingTransactions.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.green)
                    Text(t("dashboard.noUpcomingPending"))
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                    Spacer()
                }
                .padding(12)
                .finInsetSurface(cornerRadius: 14)
                .finSurfaceBorder(FinAInceColor.borderSubtle, cornerRadius: 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upcomingPendingTransactions.enumerated()), id: \.element.id) { index, transaction in
                        Button {
                            transactionToEdit = transaction
                        } label: {
                            UpcomingExpenseRow(transaction: transaction, currencyCode: currencyCode)
                        }
                        .buttonStyle(.plain)

                        if index < upcomingPendingTransactions.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(14)
                .finInsetSurface(cornerRadius: 14)
                .finSurfaceBorder(FinAInceColor.borderSubtle, cornerRadius: 14)
            }
        }
    }

    private var monthPendingCalendar: some View {
        VStack(alignment: .leading, spacing: 10) {
//            HStack {
//                Text("Calendário do mês")
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
//
//                Spacer()
//
//                Text("\(monthPendingTransactions.count) pendente\(monthPendingTransactions.count == 1 ? "" : "s")")
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
//            }

            VStack(spacing: 8) {
                calendarWeekdayHeader

                LazyVGrid(columns: calendarColumns, spacing: 4) {
                    ForEach(calendarDays, id: \.id) { day in
                        calendarDayCell(for: day)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .finInsetSurface(cornerRadius: 14)
            .finSurfaceBorder(FinAInceColor.borderSubtle, cornerRadius: 14)
        }
    }

    private var calendarWeekdayHeader: some View {
        let symbols = cal.shortWeekdaySymbols
        let firstIndex = cal.firstWeekday - 1
        let orderedSymbols = Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])

        return HStack {
            ForEach(orderedSymbols, id: \.self) { symbol in
                Text(symbol.prefix(1).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    private var calendarDays: [DashboardCalendarDay] {
        guard let firstDay = cal.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)),
              let range = cal.range(of: .day, in: .month, for: firstDay) else {
            return []
        }

        let leadingEmptyDays = (cal.component(.weekday, from: firstDay) - cal.firstWeekday + 7) % 7
        var days: [DashboardCalendarDay] = (0..<leadingEmptyDays).map { i in
            DashboardCalendarDay(emptyIndex: i)
        }

        days += range.compactMap { day -> DashboardCalendarDay? in
            guard let date = cal.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: day)) else {
                return nil
            }
            return DashboardCalendarDay(date: date)
        }

        return days
    }

    private func calendarDayCell(for day: DashboardCalendarDay) -> some View {
        Group {
            if let date = day.date {
                let transactions = pendingTransactions(for: date)
                let hasPendingTransactions = !transactions.isEmpty
                let isToday = cal.isDateInToday(date)
                Button {
                    guard !transactions.isEmpty else { return }
                    selectedCalendarDay = SelectedCalendarDay(date: date)
                } label: {
                    ZStack {
                        Circle()
                            .fill(calendarDayBackgroundColor(isToday: isToday, hasPendingTransactions: hasPendingTransactions))
                            .frame(width: 34, height: 34)

                        Text("\(cal.component(.day, from: date))")
                            .font(.caption.weight(isToday || hasPendingTransactions ? .semibold : .regular))
                            .foregroundStyle(calendarDayForegroundColor(isToday: isToday, hasPendingTransactions: hasPendingTransactions))
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isToday && !hasPendingTransactions ? Color.accentColor.opacity(0.35) : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(transactions.isEmpty)
            } else {
                Color.clear
                    .frame(minHeight: 36)
            }
        }
    }

    private func calendarDayForegroundColor(isToday: Bool, hasPendingTransactions: Bool) -> Color {
        if hasPendingTransactions { return .red }
        if isToday { return Color.accentColor }
        return .primary
    }

    private func calendarDayBackgroundColor(isToday: Bool, hasPendingTransactions: Bool) -> Color {
        if hasPendingTransactions { return Color.red.opacity(0.14) }
        if isToday { return Color.accentColor.opacity(0.1) }
        return Color.clear
    }

    // O(1) lookup — data pre-built in refreshCache()
    private func pendingTransactions(for date: Date) -> [Transaction] {
        cachedPendingByDay[cal.startOfDay(for: date)] ?? []
    }

    // MARK: - Cache refresh

    /// Rebuilds all derived State that depends on transactions / selected month / AI setup.
    private func refreshDashboardData() {
        refreshCache()
        scheduleInsightsRefresh()
    }

    private func refreshInsightsCache() {
        cachedInsights = InsightEngine.compute(
            transactions: transactions,
            accounts: accounts,
            goals: goals,
            month: selectedMonth,
            year: selectedYear,
            currencyCode: currencyCode,
            selectedAccountId: selectedAccountId
        )
    }

    private func scheduleInsightsRefresh() {
        let token = UUID()
        insightsReloadToken = token
        isInsightsLoading = true
        cachedInsights = []
        let scopedTransactions = transactions
        let scopedAccounts = accounts
        let scopedGoals = goals
        let scopedMonth = selectedMonth
        let scopedYear = selectedYear
        let scopedCurrencyCode = currencyCode
        let scopedAccountId = selectedAccountId

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15) {
            let computedInsights = InsightEngine.compute(
                transactions: scopedTransactions,
                accounts: scopedAccounts,
                goals: scopedGoals,
                month: scopedMonth,
                year: scopedYear,
                currencyCode: scopedCurrencyCode,
                selectedAccountId: scopedAccountId
            )

            DispatchQueue.main.async {
                guard token == insightsReloadToken else { return }
                cachedInsights = computedInsights
                isInsightsLoading = false
            }
        }
    }

    private func refreshCache() {
        let month     = selectedMonth
        let year      = selectedYear
        let allTx     = transactions
        let accountId = selectedAccountId

        // Month expenses (paid + pending), optionally filtered by account
        cachedMonthTx = allTx.filter { tx in
            let c = cal.dateComponents([.month, .year], from: tx.date)
            guard c.month == month, c.year == year, tx.type == .expense else { return false }
            if let accountId { return tx.account?.id == accountId }
            return true
        }

        // All unpaid expenses, optionally filtered by account, sorted by date
        cachedPendingAll = allTx
            .filter { tx in
                guard tx.type == .expense, !tx.isPaid else { return false }
                if let accountId { return tx.account?.id == accountId }
                return true
            }
            .sorted { $0.date < $1.date }

        // Pending for the selected month, keyed by day (for calendar O(1) lookup)
        var byDay: [Date: [Transaction]] = [:]
        for tx in cachedPendingAll {
            let c = cal.dateComponents([.month, .year], from: tx.date)
            guard c.month == month, c.year == year else { continue }
            let day = cal.startOfDay(for: tx.date)
            byDay[day, default: []].append(tx)
        }
        // Pre-sort each bucket so pendingTransactions(for:) is purely a dict lookup
        for key in byDay.keys {
            byDay[key]!.sort {
                if $0.amount == $1.amount { return $0.date < $1.date }
                return $0.amount > $1.amount
            }
        }
        cachedPendingByDay = byDay
    }

    private func moveMonth(by delta: Int) {
        var comps = DateComponents()
        comps.month = selectedMonth + delta; comps.year = selectedYear
        if let date = cal.date(from: comps) {
            let c = cal.dateComponents([.month, .year], from: date)
            selectedMonth = c.month!; selectedYear = c.year!
        }
    }

    // MARK: - Layout: iPhone vs iPad

    /// Single-column layout for iPhone (and compact size class).
    /// Uses eager VStack: pays the full render cost upfront (during the
    /// 200ms pre-cache pause we wait in `.task(id:)`), but then scroll is
    /// smooth — no per-section stall when new content enters the viewport.
    private var iPhoneContentStack: some View {
        VStack(spacing: 20) {
            insightsSection
            aiSetupCard
            calendarSection
            goalsSection
            projectsSection
            monthEvolutionChartCard
            chartSection
            
        }
        .padding(.horizontal)
    }

    /// Two-column layout for iPad (regular horizontal size class).
    ///
    /// Uses VStack + HStack instead of LazyVGrid to guarantee correct
    /// full-width vs. side-by-side behaviour for @ViewBuilder sections.
    /// Content is centered and capped at 1100pt so it doesn't over-stretch
    /// on large iPad Pro screens.
    private var iPadContentGrid: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    insightsSection
                    aiSetupCard
                    calendarSection
                }
                    .frame(maxWidth: .infinity)

                VStack(spacing: 20) {
                    goalsSection
                    projectsSection
                    chartSection
                }
                    .frame(maxWidth: .infinity)
            }

            monthEvolutionChartCard
            SpendingHistoryCard(transactions: transactions)
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        // Cap width on very large iPads so cards don't over-stretch
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Goals

    private var goalsSection: some View {
        VStack(spacing: 0) {
            // ── Card header ──────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                NavigationLink {
                    GoalsListView()
                } label: {
                    Text(t("dashboard.goals"))
                        .font(.headline)
                        .foregroundStyle(FinAInceColor.primaryText)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { showGoalForm = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // ── Card body ────────────────────────────────────────────────
            if activeGoals.isEmpty {
                goalsEmptyState
            } else if activeGoals.count > 2 {
                LazyVGrid(columns: compactGoalColumns(for: activeGoals.count), spacing: 8) {
                    ForEach(activeGoals) { goal in
                        CompactGoalProgressCard(
                            goal: goal,
                            spent: spentForGoal(goal),
                            forecast: forecastForGoal(goal),
                            onTap: goal.category != nil ? { drilldownCategory = goal.category } : nil
                        )
                    }
                }
                .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activeGoals.enumerated()), id: \.element.id) { idx, goal in
                        GoalProgressCard(
                            goal: goal,
                            spent: spentForGoal(goal),
                            forecast: forecastForGoal(goal),
                            onTap: goal.category != nil ? { drilldownCategory = goal.category } : nil
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if idx < activeGoals.count - 1 {
                            Divider().padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
        .modifier(DashboardCardModifier(
            fillColor: dashboardCardFillColor,
            cornerRadius: dashboardCardCornerRadius,
            showsShadow: isRegular
        ))
    }

    private func compactGoalColumns(for count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: min(count, 3))
    }

    private var goalsEmptyState: some View {
        Button { showGoalForm = true } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "target")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(t("dashboard.firstGoal"))
                        .font(.subheadline.bold())
                        .foregroundStyle(FinAInceColor.primaryText)
                    Text(t("dashboard.firstGoalDesc"))
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func spentForGoal(_ goal: Goal) -> Double {
        monthTransactions
            .filter { $0.isPaid && matchesGoal($0, goal: goal) }
            .reduce(0) { $0 + $1.amount }
    }

    private func forecastForGoal(_ goal: Goal) -> Double {
        monthTransactions
            .filter { matchesGoal($0, goal: goal) }
            .reduce(0) { $0 + $1.amount }
    }

    private func matchesGoal(_ tx: Transaction, goal: Goal) -> Bool {
        guard tx.type == .expense else { return false }
        guard let catGoal = goal.category else { return true }
        let root = tx.category?.parent ?? tx.category
        return root?.id == catGoal.id
    }

    // MARK: - Projects

    private var projectsSection: some View {
        Group {
            if activeProjects.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        NavigationLink {
                            ProjectsListView()
                        } label: {
                            Text(t("dashboard.projects"))
                                .font(.headline)
                                .foregroundStyle(FinAInceColor.primaryText)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button { showNewProjectForm = true } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider()

                    if activeProjects.count <= 3 {
                        // List layout: 1 project per line with more detail
                        VStack(spacing: 0) {
                            ForEach(activeProjects) { project in
                                Button { selectedProject = project } label: {
                                    DashboardProjectRow(
                                        project: project,
                                        spent: spentForProject(project),
                                        txCount: txCount(for: project),
                                        fileCount: fileCount(for: project),
                                        currencyCode: currencyCode
                                    )
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if project.id != activeProjects.last?.id {
                                    Divider().padding(.leading, 68)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        // Grid layout: compact cells for 4+ projects
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 8),
                                count: 3
                            ),
                            spacing: 8
                        ) {
                            ForEach(activeProjects.prefix(6)) { project in
                                Button { selectedProject = project } label: {
                                    DashboardProjectCell(
                                        project: project,
                                        spent: spentForProject(project),
                                        txCount: txCount(for: project),
                                        fileCount: fileCount(for: project),
                                        currencyCode: currencyCode
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                    }
                }
                .modifier(DashboardCardModifier(
                    fillColor: dashboardCardFillColor,
                    cornerRadius: dashboardCardCornerRadius,
                    showsShadow: isRegular
                ))
            }
        }
    }

    private func spentForProject(_ project: CostCenter) -> Double {
        transactions
            .filter { $0.costCenterId == project.id && $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }

    private func txCount(for project: CostCenter) -> Int {
        transactions.filter { $0.costCenterId == project.id }.count
    }

    private func fileCount(for project: CostCenter) -> Int {
        allCostCenterFiles.filter { $0.costCenterId == project.id }.count
    }

    // MARK: - Account Blocks

    // MARK: - Month Evolution

    private var monthEvolutionChartData: [DashboardCumulativePoint] {
        let calendar = Calendar.current
        let currentMonthSeries = t("dashboard.currentMonthSeries")
        let previousMonthSeries = t("dashboard.previousMonthSeries")
        let today = Date()
        let isCurrentMonth = calendar.component(.month, from: today) == selectedMonth
                          && calendar.component(.year, from: today) == selectedYear
        let todayDay = calendar.component(.day, from: today)
        let maxDay = isCurrentMonth ? todayDay : 31

        let previousMonth = selectedMonth == 1 ? 12 : selectedMonth - 1
        let previousYear = selectedMonth == 1 ? selectedYear - 1 : selectedYear

        let currentExpenses = monthTransactions.filter { $0.type == .expense }
        let previousExpenses = transactions.filter { transaction in
            guard transaction.type == .expense else { return false }
            let components = calendar.dateComponents([.month, .year], from: transaction.date)
            guard components.month == previousMonth, components.year == previousYear else { return false }
            if let selectedAccountId { return transaction.account?.id == selectedAccountId }
            return true
        }

        func makeCumulative(_ transactions: [Transaction], upTo maxDay: Int, series: String) -> [DashboardCumulativePoint] {
            let byDay = Dictionary(grouping: transactions) { calendar.component(.day, from: $0.date) }
            var runningTotal = 0.0

            return (1...max(1, maxDay)).map { day in
                runningTotal += byDay[day]?.reduce(0.0) { $0 + $1.amount } ?? 0
                return DashboardCumulativePoint(
                    id: "\(series)-\(day)",
                    day: day,
                    amount: runningTotal,
                    series: series
                )
            }
        }

        return makeCumulative(currentExpenses, upTo: maxDay, series: currentMonthSeries)
             + makeCumulative(previousExpenses, upTo: maxDay, series: previousMonthSeries)
    }

    private var monthEvolutionChartCard: some View {
        let data = monthEvolutionChartData
        let currentMonthSeries = t("dashboard.currentMonthSeries")
        let previousMonthSeries = t("dashboard.previousMonthSeries")
        let chartDayLabel = t("chart.day")
        let chartTotalLabel = t("dashboard.total")
        let chartSeriesLabel = t("chart.series")
        let currentPoints = data.filter { $0.series == currentMonthSeries }
        let previousPoints = data.filter { $0.series == previousMonthSeries }
        let currentTotal = currentPoints.last?.amount ?? 0
        let previousTotal = previousPoints.last?.amount ?? 0
        let hasPrevious = previousTotal.isFinite && previousTotal > 0 && currentTotal.isFinite
        let rawPercent = hasPrevious ? ((currentTotal - previousTotal) / previousTotal * 100).rounded() : 0
        let percent = rawPercent.isFinite ? Int(rawPercent) : 0

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.subheadline)
                        .foregroundStyle(.purple)
                    Text(t("transaction.monthEvolution"))
                        .font(.headline)
                }
          
                Spacer()

                if hasPrevious {
                        HStack(spacing: 4) {
                            Image(systemName: percent >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2.weight(.bold))
                            Text(t("dashboard.vsPreviousMonthValue", "\(percent >= 0 ? "+" : "")\(percent)"))
                                .font(.caption)
                        }
                        .foregroundStyle(percent > 0 ? Color.red : Color.green)
                }

                
            }

            Divider()

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
                currentMonthSeries: Color.accentColor,
                previousMonthSeries: Color.secondary.opacity(0.7)
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
                    if let amount = value.as(Double.self) {
                        AxisValueLabel {
                            Text(amount.asCurrency(currencyCode))
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .modifier(DashboardCardModifier(
            fillColor: dashboardCardFillColor,
            cornerRadius: dashboardCardCornerRadius,
            showsShadow: isRegular
        ))
        .contentShape(Rectangle())
        .onTapGesture {
            showMonthComparator = true
        }
    }

    // MARK: - Accounts

    /// Previsão de metas para uma conta específica.
    /// Para cada meta com categoria: se esta conta tem gastos nessa categoria no mês,
    /// inclui o restante da meta (target − gasto total na categoria de todas as contas).
    private func goalsForecast(for account: Account) -> Double {
        let accountMonthTx = monthTransactions.filter { $0.account?.id == account.id }

        return goals.reduce(0.0) { sum, goal in
            guard let cat = goal.category else { return sum }

            // Verifica se esta conta tem algum gasto na categoria da meta
            let accountSpent = accountMonthTx.filter { tx in
                guard tx.type == .expense else { return false }
                let root = tx.category?.parent ?? tx.category
                return root?.persistentModelID == cat.persistentModelID
                    || tx.category?.persistentModelID == cat.persistentModelID
            }.reduce(0.0) { $0 + $1.amount }

            guard accountSpent > 0 else { return sum }

            // Gasto total na categoria (todas as contas) para cálculo correto do restante
            let totalSpentInCategory = monthTransactions.filter { tx in
                guard tx.type == .expense else { return false }
                let root = tx.category?.parent ?? tx.category
                return root?.persistentModelID == cat.persistentModelID
                    || tx.category?.persistentModelID == cat.persistentModelID
            }.reduce(0.0) { $0 + $1.amount }

            return sum + max(0, goal.targetAmount - totalSpentInCategory)
        }
    }

    private var accountBlocksSection: some View {
        VStack(spacing: 0) {
            // ── Card header ──────────────────────────────────────────────
            HStack {
                Text(t("dashboard.byAccount"))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // ── Account rows ─────────────────────────────────────────────
            VStack(spacing: 0) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { idx, account in
                    AccountExpenseBlock(
                        account: account,
                        transactions: monthTransactions.filter { $0.account?.id == account.id },
                        allTransactions: transactions,
                        selectedMonth: selectedMonth,
                        selectedYear: selectedYear,
                        currencyCode: currencyCode,
                        goalsForecast: goalsForecast(for: account)
                    )

                    if idx < accounts.count - 1 {
                        Divider().padding(.horizontal, 14)
                    }
                }
            }
        }
        .modifier(DashboardCardModifier(
            fillColor: dashboardCardFillColor,
            cornerRadius: dashboardCardCornerRadius,
            showsShadow: isRegular
        ))
    }

    // MARK: - Chart

    private var chartSection: some View {
        chartCard
    }

    private var categoryChartEmptyState: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                Chart([1], id: \.self) { value in
                    SectorMark(
                        angle: .value("Valor", value),
                        innerRadius: .ratio(0.58),
                        angularInset: 2
                    )
                    .foregroundStyle(Color(.systemGray5))
                    .cornerRadius(4)
                }
                .frame(width: 130, height: 130)

                VStack(spacing: 2) {
                    Text(t("dashboard.total"))
                        .font(.caption2)
                        .foregroundStyle(FinAInceColor.secondaryText)
                    Text(0.0.asCurrency(currencyCode))
                        .font(.caption.bold())
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(t("dashboard.noSpendingMonth"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FinAInceColor.primaryText)
                Text(t("dashboard.noSpendingMonthDesc"))
                    .font(.caption)
                    .foregroundStyle(FinAInceColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Card header ──────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "chart.pie.fill")
                    .font(.subheadline)
                    .foregroundStyle(.pink)
                Text(t("dashboard.byCategory"))
                    .font(.headline)
                Spacer()
                if !expensesByCategory.isEmpty {
                    Image(systemName: "chevron.up.forward")
                        .font(.caption.bold())
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // ── Card body ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 16) {
            if expensesByCategory.isEmpty {
                categoryChartEmptyState
            } else {
                HStack(alignment: .center, spacing: 20) {
                    ZStack {
                        Chart(expensesByCategory, id: \.category.id) { item in
                            SectorMark(
                                angle: .value("Valor", item.total),
                                innerRadius: .ratio(0.58),
                                angularInset: 2
                            )
                            .foregroundStyle(Color(hex: item.category.color))
                            .cornerRadius(4)
                        }
                        .frame(width: 150, height: 150)

                        VStack(spacing: 2) {
                            Text(t("dashboard.total"))
                                .font(.caption2)
                                .foregroundStyle(FinAInceColor.secondaryText)
                            Text(totalExpensesRealized.asCurrency(currencyCode))
                                .font(.caption.bold())
                                .minimumScaleFactor(0.5)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 72)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(expensesByCategory.prefix(5), id: \.category.id) { item in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: item.category.color))
                                    .frame(width: 8, height: 8)
                                Text(item.category.displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(totalExpensesRealized > 0 ? item.total / totalExpensesRealized * 100 : 0))%")
                                    .font(.caption.bold())
                                    .foregroundStyle(FinAInceColor.secondaryText)
                            }
                        }
                        if expensesByCategory.count > 5 {
                            Text(t("dashboard.moreCount", expensesByCategory.count - 5))
                                .font(.caption2)
                                .foregroundStyle(FinAInceColor.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            }   // end VStack body
            .padding(16)
        }
        .modifier(DashboardCardModifier(
            fillColor: dashboardCardFillColor,
            cornerRadius: dashboardCardCornerRadius,
            showsShadow: isRegular
        ))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !expensesByCategory.isEmpty else { return }
            showCategoryDetails = true
        }
    }

    private var dashboardWorkspaceBackground: some View {
        WorkspaceBackground(isRegularLayout: isRegular)
    }

}

private struct DashboardCardModifier: ViewModifier {
    let fillColor: Color
    let cornerRadius: CGFloat
    let showsShadow: Bool

    func body(content: Content) -> some View {
        content
            .background(fillColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(FinAInceColor.borderSubtle, lineWidth: 1)
            )
            .shadow(color: showsShadow ? Color.black.opacity(0.05) : .clear, radius: 18, y: 10)
    }
}

private struct DashboardCumulativePoint: Identifiable {
    let id: String
    let day: Int
    let amount: Double
    let series: String
}

private struct SelectedCalendarDay: Identifiable {
    let date: Date

    var id: Date { date }
}

private struct DashboardCalendarDay: Identifiable {
    /// Stable string ID so SwiftUI doesn't destroy/recreate cells on every render.
    let id: String
    let date: Date?

    /// Real calendar day.
    init(date: Date) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.id   = "\(c.year!)-\(c.month!)-\(c.day!)"
        self.date = date
    }

    /// Leading empty placeholder; index makes the id stable.
    init(emptyIndex: Int) {
        self.id   = "empty-\(emptyIndex)"
        self.date = nil
    }
}

private struct UpcomingExpenseRow: View {
    let transaction: Transaction
    let currencyCode: String

    private var dateText: String {
        transaction.date.formatted(.dateTime.day().month(.abbreviated).locale(LanguageManager.shared.effective.locale))
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: transaction.subcategory?.icon ?? transaction.category?.icon ?? "calendar.badge.clock")
                    .font(.subheadline)
                    .foregroundStyle(Color.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.placeName ?? transaction.category?.displayName ?? t("dashboard.pending"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FinAInceColor.primaryText)
                    .lineLimit(1)

                Text(dateText.capitalized)
                    .font(.caption)
                    .foregroundStyle(FinAInceColor.secondaryText)
            }

            Spacer()

            Text(transaction.amount.asCurrency(currencyCode))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FinAInceColor.primaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct PendingDayTransactionsSheet: View {
    let date: Date
    let transactions: [Transaction]

    @Environment(\.dismiss) private var dismiss
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode
    @State private var transactionToEdit: Transaction?

    private var title: String {
        date.formatted(.dateTime.day().month(.wide).locale(LanguageManager.shared.effective.locale)).capitalized
    }

    private var total: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)
                            Text(t(transactions.count == 1 ? "dashboard.pendingExpenseSingular" : "dashboard.pendingExpensePlural", transactions.count))
                                .font(.subheadline)
                                .foregroundStyle(FinAInceColor.secondaryText)
                        }

                        Spacer()

                        Text(total.asCurrency(currencyCode))
                            .font(.headline)
                            .foregroundStyle(.red)
                    }
                    .padding(.vertical, 4)
                }

                Section(t("dashboard.transactions")) {
                    ForEach(transactions) { transaction in
                        TransactionRowView(transaction: transaction, showAccount: true)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                transactionToEdit = transaction
                            }
                    }
                }
            }
            .navigationTitle(t("dashboard.dayExpenses"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.close")) { dismiss() }
                }
            }
            .sheet(item: $transactionToEdit) { transaction in
                TransactionEditView(transaction: transaction)
            }
        }
    }
}

// MARK: - Category Details Sheet

private struct CategoryDetailsSheet: View {
    let expensesByCategory: [(category: Category, total: Double)]
    let total: Double
    let transactions: [Transaction]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: Category?

    var body: some View {
        NavigationStack {
            ZStack {
                FinAInceColor.groupedBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(t("dashboard.detail"))
                            .font(.title3.bold())
                            .foregroundStyle(FinAInceColor.primaryText)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        Text(t("dashboard.categoryTapHint"))
                            .font(.subheadline)
                            .foregroundStyle(FinAInceColor.secondaryText)
                            .padding(.horizontal)

                        VStack(spacing: 0) {
                            ForEach(Array(expensesByCategory.enumerated()), id: \.element.category.id) { index, item in
                                CategoryRowView(
                                    category: item.category,
                                    amount: item.total,
                                    total: total
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedCategory = item.category
                                }

                                if index < expensesByCategory.count - 1 {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .padding(16)
                        .finElevatedSurface(cornerRadius: 14)
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(t("dashboard.byCategory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FinAInceColor.primarySurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.close")) { dismiss() }
                }
            }
            .sheet(item: $selectedCategory) { category in
                CategoryDrilldownView(category: category, transactions: transactions)
            }
        }
    }
}

// MARK: - Account Expense Block (collapsible)

struct AccountExpenseBlock: View {
    let account: Account
    let transactions: [Transaction]
    let allTransactions: [Transaction]
    let selectedMonth: Int
    let selectedYear: Int
    let currencyCode: String
    var goalsForecast: Double = 0

    @State private var isExpanded = false

    private var cal: Calendar { Calendar.current }

    var paid: Double    { transactions.filter {  $0.isPaid }.reduce(0) { $0 + $1.amount } }
    var pending: Double { transactions.filter { !$0.isPaid }.reduce(0) { $0 + $1.amount } }
    var total: Double   { paid + pending }
    /// Previsto = transações pendentes + restante das metas ativas
    var forecast: Double { pending + goalsForecast }

    var billingInfo: (total: Double, start: Date, end: Date)? {
        guard account.type == .creditCard,
              let startDay = account.ccBillingStartDay,
              let endDay   = account.ccBillingEndDay else { return nil }

        let now = Date()
        let todayDay = cal.component(.day, from: now)

        let cycleStartComponents: DateComponents
        if todayDay >= startDay {
            cycleStartComponents = DateComponents(
                year:  cal.component(.year,  from: now),
                month: cal.component(.month, from: now),
                day:   startDay
            )
        } else {
            let prev = cal.date(byAdding: .month, value: -1, to: now)!
            cycleStartComponents = DateComponents(
                year:  cal.component(.year,  from: prev),
                month: cal.component(.month, from: prev),
                day:   startDay
            )
        }

        guard let cycleStart = cal.date(from: cycleStartComponents) else { return nil }
        let cycleEndBase = cal.date(byAdding: .month, value: 1, to: cycleStart)!
        guard let cycleEnd = cal.date(from: DateComponents(
            year:  cal.component(.year,  from: cycleEndBase),
            month: cal.component(.month, from: cycleEndBase),
            day:   endDay
        )) else { return nil }

        let cycleTotal = allTransactions
            .filter {
                $0.account?.id == account.id &&
                $0.type == .expense &&
                $0.date >= cycleStart &&
                $0.date <= cycleEnd
            }
            .reduce(0) { $0 + $1.amount }

        return (cycleTotal, cycleStart, cycleEnd)
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Collapsed row (always visible) ──────────────────────────
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    // Ícone
                    Image(systemName: account.icon)
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: account.color))
                        .frame(width: 36, height: 36)
                        .background(Color(hex: account.color).opacity(0.15))
                        .clipShape(Circle())

                    // Nome + tipo
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(account.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(FinAInceColor.primaryText)
                            if account.isDefault {
                                Text(t("common.default"))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(account.type.label)
                            .font(.caption)
                            .foregroundStyle(FinAInceColor.secondaryText)
                    }

                    Spacer()

                    // Valor total + chevron
                    HStack(spacing: 6) {
                        Text(total.asCurrency(currencyCode))
                            .font(.subheadline.bold())
                            .foregroundStyle(FinAInceColor.primaryText)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(FinAInceColor.secondaryText)
                    }
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // ── Expanded content ─────────────────────────────────────────
            if isExpanded {
                VStack(spacing: 12) {
                    Divider()
                        .padding(.horizontal, 14)

                    if account.type == .creditCard, let billing = billingInfo {
                        VStack(spacing: 10) {
                            HStack {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                    .foregroundStyle(FinAInceColor.secondaryText)
                                Text(t(
                                    "dashboard.invoiceWindow",
                                    billing.start.formatted(.dateTime.day().month(.abbreviated)),
                                    billing.end.formatted(.dateTime.day().month(.abbreviated))
                                ))
                                    .font(.caption)
                                    .foregroundStyle(FinAInceColor.secondaryText)
                                Spacer()
                            }
                            .padding(.horizontal, 14)

                            HStack(spacing: 0) {
                                accountStatItem(label: "Realizado", amount: paid, color: .primary)
                                Divider().frame(height: 32)
                                accountStatItem(label: "A pagar", amount: pending, color: .orange)
                                Divider().frame(height: 32)
                                accountStatItem(label: "Fatura est.", amount: billing.total, color: .red)
                            }
                            .padding(.horizontal, 14)
                        }
                    } else {
                        HStack(spacing: 0) {
                            accountStatItem(label: "Realizado", amount: paid, color: .primary)
                            Divider().frame(height: 32)
                            accountStatItem(label: "Previsto", amount: forecast, color: .orange)
                        }
                        .padding(.horizontal, 14)
                    }

                    // Mini barra de progresso — usa forecast como total esperado
                    let progressTotal = max(total, paid + forecast)
                    if progressTotal > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.orange.opacity(0.2))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: account.color))
                                    .frame(width: geo.size.width * min(paid / progressTotal, 1), height: 4)
                                    .animation(.easeOut(duration: 0.4), value: paid)
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 14)

                        HStack {
                            Text(t("dashboard.percentDoneValue", Int(paid / progressTotal * 100)))
                                .font(.caption2)
                                .foregroundStyle(FinAInceColor.secondaryText)
                            Spacer()
                            if goalsForecast > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "target")
                                        .font(.system(size: 9))
                                    Text(goalsForecast.asCurrency(currencyCode))
                                        .font(.caption2)
                                }
                                .foregroundStyle(FinAInceColor.secondaryText)
                            }
                        }
                        .padding(.horizontal, 14)
                    }

                    Spacer().frame(height: 4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func accountStatItem(label: String, amount: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(FinAInceColor.secondaryText)
            Text(amount.asCurrency(currencyCode))
                .font(.caption.bold())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}


// MARK: - Category Row

struct CategoryRowView: View {
    let category: Category
    let amount: Double
    let total: Double
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    var percentage: Double { total > 0 ? amount / total : 0 }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: category.color).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: category.icon)
                    .font(.headline)
                    .foregroundStyle(Color(hex: category.color))
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(category.displayName)
                        .font(.headline)
                        .foregroundStyle(FinAInceColor.primaryText)
                    Spacer()
                    Text(amount.asCurrency(currencyCode))
                        .font(.headline.bold())
                        .foregroundStyle(FinAInceColor.primaryText)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.systemGray5))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: category.color))
                            .frame(width: geo.size.width * percentage, height: 6)
                    }
                }
                .frame(height: 6)
                Text(t("dashboard.percentOfSpendingValue", Int(percentage * 100)))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(FinAInceColor.secondaryText)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Month Selector (usado no Extrato)

struct MonthSelectorView: View {
    @Binding var month: Int
    @Binding var year: Int

    var title: String {
        var comps = DateComponents()
        comps.month = month; comps.year = year; comps.day = 1
        let date = Calendar.current.date(from: comps) ?? Date()
        let fmt = DateFormatter()
        fmt.locale = LanguageManager.shared.effective.locale
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date).capitalized
    }

    var body: some View {
        HStack {
            Button { move(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.bold())
                    .foregroundStyle(FinAInceColor.primaryText)
                    .frame(width: 36, height: 36)
                    .background(FinAInceColor.secondarySurface)
                    .clipShape(Circle())
            }
            Text(title).font(.headline).frame(maxWidth: .infinity)
            Button { move(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(FinAInceColor.primaryText)
                    .frame(width: 36, height: 36)
                    .background(FinAInceColor.secondarySurface)
                    .clipShape(Circle())
            }
        }
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

private struct DashboardInsightAnalysisSharePayload: Identifiable {
    let id = UUID()
    let fileURL: URL
}

private struct DashboardInsightAnalysisEducationDialog: View {
    let insight: Insight
    let onCancel: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.white.opacity(0.18), lineWidth: 1)
                            )
                            .frame(width: 58, height: 58)
                        Image(systemName: insight.icon)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                    }

                    Text(t("dashboard.insightAnalysisSheetTitle"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(t("dashboard.insightAnalysisSheetSubtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, insight.color.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(t("dashboard.quickAnalysisTitle"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(FinAInceColor.secondaryText)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(insight.title)
                                .font(.headline)
                                .foregroundStyle(FinAInceColor.primaryText)
                            Text(insight.body)
                                .font(.subheadline)
                                .foregroundStyle(FinAInceColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .finInsetSurface(cornerRadius: 14)
                    }

                    VStack(spacing: 0) {
                        dashboardInsightStepRow(icon: "doc.text.fill", text: t("dashboard.insightAnalysisStep1"))
                        dashboardInsightStepConnector
                        dashboardInsightStepRow(icon: "square.and.arrow.up.fill", text: t("dashboard.insightAnalysisStep2"))
                        dashboardInsightStepConnector
                        dashboardInsightStepRow(icon: "sparkles", text: t("dashboard.insightAnalysisStep3"))
                    }
                    .padding(.vertical, 4)

                    VStack(spacing: 8) {
                        Button(action: onContinue) {
                            Text(t("dashboard.viewWithAI"))
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button(action: onCancel) {
                            Text(t("common.cancel"))
                                .font(.subheadline)
                                .foregroundStyle(FinAInceColor.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .background(FinAInceColor.primarySurface)
    }

    private func dashboardInsightStepRow(icon: String, text: String) -> some View {
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
                .foregroundStyle(FinAInceColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var dashboardInsightStepConnector: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 1.5, height: 10)
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
    }
}

// MARK: - Dashboard Project Row (list layout, ≤3 projects)

private struct DashboardProjectRow: View {
    let project: CostCenter
    let spent: Double
    let txCount: Int
    let fileCount: Int
    let currencyCode: String

    private var metaLabel: String {
        var parts: [String] = []
        if txCount > 0 { parts.append("\(txCount) transaç\(txCount == 1 ? "ão" : "ões")") }
        if fileCount > 0 { parts.append("\(fileCount) arquivo\(fileCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: project.color).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: project.icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(hex: project.color))
                }

                // Name + meta
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if !metaLabel.isEmpty {
                        Text(metaLabel)
                            .font(.caption)
                            .foregroundStyle(FinAInceColor.secondaryText)
                    }
                }

                Spacer()

                // Spent
                Text(spent.asCurrency(currencyCode))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FinAInceColor.primaryText)
            }

            // Budget progress bar — only when budget is set
            if let budget = project.budget, budget > 0 {
                ProgressView(value: project.budgetProgress(spent: spent))
                    .tint(project.budgetStatus(spent: spent).color)
                    .frame(height: 4)
                    .padding(.leading, 56) // align under name
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Dashboard Project Cell (grid layout, >3 projects)

private struct DashboardProjectCell: View {
    let project: CostCenter
    let spent: Double
    let txCount: Int
    let fileCount: Int
    let currencyCode: String

    private var metaLabel: String {
        var parts: [String] = []
        if txCount > 0 { parts.append("\(txCount) tx") }
        if fileCount > 0 { parts.append("\(fileCount) arq") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: project.color).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: project.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(hex: project.color))
            }

            VStack(spacing: 2) {
                Text(project.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(spent.asCurrency(currencyCode))
                    .font(.caption2)
                    .foregroundStyle(FinAInceColor.secondaryText)
                if !metaLabel.isEmpty {
                    Text(metaLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let budget = project.budget, budget > 0 {
                ProgressView(value: project.budgetProgress(spent: spent))
                    .tint(project.budgetStatus(spent: spent).color)
                    .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .finInsetSurface(cornerRadius: 12)
    }
}

private struct DashboardInsightAnalysisShareSheet: UIViewControllerRepresentable {
    let payload: DashboardInsightAnalysisSharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [payload.fileURL],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
