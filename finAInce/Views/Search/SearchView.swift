import SwiftUI
import SwiftData

// MARK: - Search Filter

enum SearchFilterType: CaseIterable, Identifiable {
    case all, transactions, categories, goals, projects, files

    var id: Self { self }

    var icon: String {
        switch self {
        case .all:          return "sparkles"
        case .transactions: return "arrow.up.circle"
        case .categories:   return "tag"
        case .goals:        return "target"
        case .projects:     return "folder"
        case .files:        return "doc"
        }
    }

    func label() -> String {
        switch self {
        case .all:          return t("search.filterAll")
        case .transactions: return t("search.filterTransactions")
        case .categories:   return t("search.filterCategories")
        case .goals:        return t("search.filterGoals")
        case .projects:     return t("search.filterProjects")
        case .files:        return t("search.filterFiles")
        }
    }
}

// MARK: - File Search Result

struct SearchFileResult: Identifiable {
    let id: UUID
    let name: String
    let url: URL?
    let subtitle: String
    let icon: String
    let iconColor: Color
}

// MARK: - Identifiable URL wrapper (for sheet)

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Search Trigger (drives .task(id:) re-runs)

private struct SearchTrigger: Equatable {
    let text: String
    let from: Date
    let to:   Date
}

// MARK: - SearchView

struct SearchView: View {

    // MARK: Queries
    @Query(sort: \Transaction.date, order: .reverse)
    private var allTransactions: [Transaction]

    @Query(sort: \Category.sortOrder)
    private var allCategories: [Category]

    @Query(sort: \Goal.createdAt)
    private var allGoals: [Goal]

    @Query(sort: \CostCenter.name)
    private var allProjects: [CostCenter]

    @Query(sort: \CostCenterFile.fileName)
    private var allProjectFiles: [CostCenterFile]

    @Query(sort: \ReceiptAttachment.fileName)
    private var allReceiptAttachments: [ReceiptAttachment]

    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    // MARK: State
    @State private var searchText   = ""
    @State private var dateFrom: Date = Calendar.current.date(byAdding: .year, value: -5, to: Date()) ?? Date()
    @State private var dateTo: Date  = {
        var comps = Calendar.current.dateComponents([.year, .month], from: Date())
        comps.month = (comps.month ?? 1) + 1
        comps.day   = 0
        return Calendar.current.date(from: comps) ?? Date()
    }()
    @State private var selectedFilter: SearchFilterType = .all
    @State private var showDateFilters = false
    @State private var previewItem: IdentifiableURL?
    @State private var selectedGoal: Goal?
    @State private var showGoalSheet = false
    @FocusState private var searchFocused: Bool
    private let regularContentMaxWidth: CGFloat = 1100

    // MARK: - Debounced results (computed off the keystroke)
    @State private var filteredTransactions: [Transaction] = []
    @State private var filteredCategories: [Category]     = []
    @State private var filteredGoals: [Goal]              = []
    @State private var filteredProjects: [CostCenter]     = []
    @State private var filteredFiles: [SearchFileResult]  = []
    @State private var isSearching: Bool = false

    // MARK: - Computed

    private var trimmed: String { searchText.trimmingCharacters(in: .whitespaces) }
    private var isSearchActive: Bool { trimmed.count >= 2 }
    private var query: String { trimmed.lowercased() }
    private var isRegularLayout: Bool { horizontalSizeClass == .regular }
    private var selectedFilterBadgeFill: Color { .white.opacity(0.3) }
    private var regularHeaderTopColor: Color {
        colorScheme == .dark ? Color(red: 0.26, green: 0.19, blue: 0.58) : Color.accentColor.opacity(0.96)
    }
    private var regularHeaderBottomColor: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.10, blue: 0.24) : Color.accentColor.opacity(0.72)
    }

    private var totalCount: Int {
        filteredTransactions.count
        + filteredCategories.count
        + filteredGoals.count
        + filteredProjects.count
        + filteredFiles.count
    }

    private func count(for filter: SearchFilterType) -> Int {
        switch filter {
        case .all:          return totalCount
        case .transactions: return filteredTransactions.count
        case .categories:   return filteredCategories.count
        case .goals:        return filteredGoals.count
        case .projects:     return filteredProjects.count
        case .files:        return filteredFiles.count
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isRegularLayout {
                    regularSearchView
                } else {
                    compactSearchView
                }
            }
            .toolbar {
                if isSearchActive && !isRegularLayout {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(t("search.clearSearch")) {
                            searchText    = ""
                            selectedFilter = .all
                            searchFocused  = false
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .sheet(item: $previewItem) { item in
                SearchFilePreviewSheet(url: item.url)
            }
            .sheet(isPresented: $showGoalSheet) {
                if let goal = selectedGoal {
                    GoalFormView(goal: goal)
                }
            }
            .onAppear { initDateRange() }
            .task(id: SearchTrigger(text: trimmed, from: dateFrom, to: dateTo)) {
                await runDebouncedSearch()
            }
        }
    }

    private var compactSearchView: some View {
        GeometryReader { proxy in
            ZStack {
                WorkspaceBackground(isRegularLayout: false)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    compactSearchHeader(topInset: proxy.safeAreaInsets.top)
                        .ignoresSafeArea(edges: .top)

                    searchContent
                        .background(Color.clear)
                }.padding(.top, -50)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            searchBarRow
            if !isRegularLayout {
                Divider()
            }
            if !isSearchActive {
                emptyPrompt
                    .contentShape(Rectangle())
                    .onTapGesture { searchFocused = false }
            } else if isSearching && totalCount == 0 {
                loadingView
                    .contentShape(Rectangle())
                    .onTapGesture { searchFocused = false }
            } else if totalCount == 0 {
                noResultsView
                    .contentShape(Rectangle())
                    .onTapGesture { searchFocused = false }
            } else {
                VStack(spacing: 0) {
                    filterChipsRow
                    ZStack(alignment: .top) {
                        resultsList
                        if isSearching {
                            inlineSearchingBar
                        }
                    }
                }
            }
        }
    }

    private var regularSearchView: some View {
        GeometryReader { proxy in
            ZStack {
                WorkspaceBackground(isRegularLayout: true)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    regularSearchHeader(topInset: proxy.safeAreaInsets.top)
                        .ignoresSafeArea(edges: .top)

                    searchContent
                        .frame(maxWidth: regularContentMaxWidth)
                        .frame(maxWidth: .infinity)
                        .background(Color.clear)
                        .padding(.top, 24)
                }.padding(.top, -50)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func compactSearchHeader(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("search.title"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(t("search.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 20)
        .padding(.top, topInset + 16)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    regularHeaderTopColor,
                    regularHeaderBottomColor
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 28, bottomTrailing: 28))
        )
        .shadow(color: regularHeaderBottomColor.opacity(colorScheme == .dark ? 0.28 : 0.20), radius: 14, x: 0, y: 8)
    }

    private func regularSearchHeader(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("search.title"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(t("search.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 18)
        .padding(.bottom, 22)
        .frame(maxWidth: regularContentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    regularHeaderTopColor,
                    regularHeaderBottomColor
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 28, bottomTrailing: 28))
        )
        .shadow(color: regularHeaderBottomColor.opacity(colorScheme == .dark ? 0.28 : 0.20), radius: 14, x: 0, y: 8)
    }

    // MARK: - Inline loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(t("common.loading"))
                .font(.subheadline)
                .foregroundStyle(FinAInceColor.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inlineSearchingBar: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(t("common.loading"))
                .font(.caption.weight(.medium))
                .foregroundStyle(FinAInceColor.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Search Bar

    private var searchBarRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FinAInceColor.secondaryText)
                    .font(.system(size: 17, weight: .medium))

                TextField(t("search.placeholder"), text: $searchText)
                    .focused($searchFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onChange(of: searchText) { _, newValue in
                        if newValue.trimmingCharacters(in: .whitespaces).count < 2 {
                            selectedFilter = .all
                        }
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText    = ""
                        selectedFilter = .all
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(FinAInceColor.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .finInputFieldSurface(cornerRadius: isRegularLayout ? 16 : 12)
            .shadow(
                color: isRegularLayout ? FinAInceColor.borderSubtle : .clear,
                radius: 10,
                x: 0,
                y: 4
            )

           // dateRangeRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var dateRangeRow: some View {
        HStack(spacing: 10) {
            Label(t("search.period"), systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(FinAInceColor.secondaryText)

            Spacer()

            datePill(label: t("search.dateFrom"), date: $dateFrom)
            Text("→")
                .font(.caption)
                .foregroundStyle(.tertiary)
            datePill(label: t("search.dateTo"), date: $dateTo)
        }
    }

    private func datePill(label: String, date: Binding<Date>) -> some View {
        DatePicker(
            label,
            selection: date,
            displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .labelsHidden()
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(FinAInceColor.tertiarySurface)
        .clipShape(Capsule())
    }

    // MARK: - Filter Chips

    private var filterChipsRow: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SearchFilterType.allCases) { filter in
                        let cnt = count(for: filter)
                        if filter == .all || cnt > 0 {
                            filterChip(filter: filter, count: filter == .all ? totalCount : cnt)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color.clear)
            if !isRegularLayout {
                Divider()
            }
        }
    }

    private func filterChip(filter: SearchFilterType, count: Int) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFilter = filter
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: filter.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(filter.label())
                    .font(.subheadline.weight(.medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? selectedFilterBadgeFill : Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor : FinAInceColor.secondarySurface)
            .foregroundStyle(isSelected ? FinAInceColor.inverseText : FinAInceColor.primaryText)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            switch selectedFilter {
            case .all:
                allSections
            case .transactions:
                transactionSection(transactions: filteredTransactions)
            case .categories:
                categorySection(categories: filteredCategories)
            case .goals:
                goalsSection(goals: filteredGoals)
            case .projects:
                projectsSection(projects: filteredProjects)
            case .files:
                filesSection(files: filteredFiles)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(
            Group {
                if isRegularLayout {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(FinAInceColor.elevatedSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(FinAInceColor.borderSubtle, lineWidth: 1)
                        )
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: isRegularLayout ? 22 : 0, style: .continuous))
        .scrollDismissesKeyboard(.immediately)
        .animation(.easeInOut(duration: 0.2), value: selectedFilter)
    }

    @ViewBuilder
    private var allSections: some View {
        if !filteredTransactions.isEmpty {
            transactionSection(transactions: filteredTransactions)
        }
        if !filteredCategories.isEmpty {
            categorySection(categories: filteredCategories)
        }
        if !filteredGoals.isEmpty {
            goalsSection(goals: filteredGoals)
        }
        if !filteredProjects.isEmpty {
            projectsSection(projects: filteredProjects)
        }
        if !filteredFiles.isEmpty {
            filesSection(files: filteredFiles)
        }
    }

    // MARK: - Transaction Section

    @ViewBuilder
    private func transactionSection(transactions: [Transaction]) -> some View {
        Section {
            ForEach(transactions) { tx in
                NavigationLink {
                    TransactionEditView(transaction: tx)
                } label: {
                    transactionRow(tx)
                }
            }
        } header: {
            sectionHeader(
                icon: "arrow.up.circle",
                title: t("search.sectionTransactions"),
                count: transactions.count
            )
        }
    }

    private func transactionRow(_ tx: Transaction) -> some View {
        HStack(spacing: 12) {
            // Category icon circle
            ZStack {
                Circle()
                    .fill(Color(hex: tx.category?.color ?? "#8E8E93").opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: tx.category?.icon ?? "questionmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: tx.category?.color ?? "#8E8E93"))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.placeName ?? tx.category?.displayName ?? "—")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let cat = tx.subcategory ?? tx.category {
                        Text(cat.displayName)
                            .font(.caption)
                            .foregroundStyle(FinAInceColor.secondaryText)
                    }
                    if tx.notes != nil {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(tx.amount.asCurrency(currencyCode))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tx.type == .expense ? FinAInceColor.primaryText : Color.accentColor)
                Text(tx.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Category Section

    @ViewBuilder
    private func categorySection(categories: [Category]) -> some View {
        Section {
            ForEach(categories) { cat in
                let catTransactions = allTransactions.filter {
                    $0.category?.id == cat.id || $0.subcategory?.id == cat.id
                }
                NavigationLink {
                    CategoryDrilldownView(category: cat, transactions: catTransactions)
                } label: {
                    categoryRow(cat, transactionCount: catTransactions.count)
                }
            }
        } header: {
            sectionHeader(
                icon: "tag",
                title: t("search.sectionCategories"),
                count: categories.count
            )
        }
    }

    private func categoryRow(_ cat: Category, transactionCount: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: cat.color).opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: cat.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: cat.color))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cat.displayName)
                    .font(.subheadline.weight(.medium))
                if let parent = cat.parent {
                    Text(parent.displayName)
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
            }

            Spacer()

            Text("\(transactionCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FinAInceColor.secondaryText)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Goals Section

    @ViewBuilder
    private func goalsSection(goals: [Goal]) -> some View {
        Section {
            ForEach(goals) { goal in
                Button {
                    selectedGoal = goal
                    showGoalSheet = true
                } label: {
                    goalRow(goal)
                }
                .buttonStyle(.plain)
            }
        } header: {
            sectionHeader(
                icon: "target",
                title: t("search.sectionGoals"),
                count: goals.count
            )
        }
    }

    private func goalRow(_ goal: Goal) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Text(goal.emoji)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FinAInceColor.primaryText)
                if let cat = goal.category {
                    Text(cat.displayName)
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(goal.targetAmount.asCurrency(currencyCode))
                    .font(.subheadline.weight(.semibold))
                if !goal.isActive {
                    Text(t("projects.inactive"))
                        .font(.caption2)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Projects Section

    @ViewBuilder
    private func projectsSection(projects: [CostCenter]) -> some View {
        Section {
            ForEach(projects) { project in
                NavigationLink {
                    ProjectDetailView(project: project)
                } label: {
                    projectRow(project)
                }
            }
        } header: {
            sectionHeader(
                icon: "folder",
                title: t("search.sectionProjects"),
                count: projects.count
            )
        }
    }

    private func projectRow(_ project: CostCenter) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: project.color).opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: project.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: project.color))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.subheadline.weight(.medium))
                if let desc = project.desc, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !project.isActive {
                Text(t("projects.inactive"))
                    .font(.caption2)
                    .foregroundStyle(FinAInceColor.secondaryText)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Files Section

    @ViewBuilder
    private func filesSection(files: [SearchFileResult]) -> some View {
        Section {
            ForEach(files) { file in
                Button {
                    if let url = file.url {
                        previewItem = IdentifiableURL(url: url)
                    }
                } label: {
                    fileRow(file)
                }
                .buttonStyle(.plain)
                .disabled(file.url == nil)
            }
        } header: {
            sectionHeader(
                icon: "doc",
                title: t("search.sectionFiles"),
                count: files.count
            )
        }
    }

    private func fileRow(_ file: SearchFileResult) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(file.iconColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: file.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(file.iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FinAInceColor.primaryText)
                    .lineLimit(1)
                Text(file.subtitle)
                    .font(.caption)
                    .foregroundStyle(FinAInceColor.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            if file.url != nil {
                Image(systemName: "eye")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Section Header

    private func sectionHeader(icon: String, title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
        }
        .foregroundStyle(FinAInceColor.secondaryText)
    }

    // MARK: - Empty States

    private var emptyPrompt: some View {
        VStack(spacing: 24) {
            

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 96, height: 96)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 8) {
                Text(t("search.typeToSearch"))
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text(t("search.typeToSearchDesc"))
                    .font(.subheadline)
                    .foregroundStyle(FinAInceColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private var noResultsView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: 88, height: 88)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(FinAInceColor.secondaryText)
            }

            VStack(spacing: 8) {
                Text(t("search.noResults"))
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text(t("search.noResultsDesc"))
                    .font(.subheadline)
                    .foregroundStyle(FinAInceColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func initDateRange() {
        if let earliest = allTransactions.min(by: { $0.date < $1.date })?.date {
            dateFrom = Calendar.current.startOfDay(for: earliest)
        }
    }

    // MARK: - Debounced filtering

    @MainActor
    private func runDebouncedSearch() async {
        // If user cleared the field, drop results immediately and skip the work.
        guard isSearchActive else {
            withAnimation(.easeInOut(duration: 0.15)) {
                filteredTransactions = []
                filteredCategories   = []
                filteredGoals        = []
                filteredProjects     = []
                filteredFiles        = []
                isSearching          = false
            }
            return
        }

        // Show spinner while we wait the debounce window.
        withAnimation(.easeInOut(duration: 0.15)) { isSearching = true }

        // Debounce: a fresh keystroke cancels this task and re-enters,
        // so the heavy compute below only runs after the user pauses ~300ms.
        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return // cancelled by next keystroke
        }
        guard !Task.isCancelled else { return }

        // Snapshot inputs (avoid re-reading volatile state mid-loop).
        let q  = query
        let dF = dateFrom
        let dT = dateTo
        let cur = currencyCode

        // SwiftData models aren't Sendable — keep the loop on the main actor,
        // but yield periodically so the UI remains responsive on large stores.
        var txResults: [Transaction] = []
        txResults.reserveCapacity(64)
        for (i, tx) in allTransactions.enumerated() {
            if Task.isCancelled { return }
            if i % 200 == 0 { await Task.yield() }
            guard tx.date >= dF && tx.date <= dT else { continue }
            let match = (tx.placeName?.lowercased().contains(q) == true)
                || (tx.notes?.lowercased().contains(q) == true)
                || (tx.category?.displayName.lowercased().contains(q) == true)
                || (tx.subcategory?.displayName.lowercased().contains(q) == true)
                || tx.amount.asCurrency(cur).contains(q)
            if match { txResults.append(tx) }
        }

        if Task.isCancelled { return }
        let catResults = allCategories.filter { cat in
            cat.displayName.lowercased().contains(q)
            || (cat.parent?.displayName.lowercased().contains(q) == true)
        }.sorted { $0.displayName < $1.displayName }

        if Task.isCancelled { return }
        let goalResults = allGoals
            .filter { $0.title.lowercased().contains(q) }
            .sorted { $0.title < $1.title }

        if Task.isCancelled { return }
        let projectResults = allProjects.filter { project in
            project.name.lowercased().contains(q)
            || (project.desc?.lowercased().contains(q) == true)
        }.sorted { $0.name < $1.name }

        if Task.isCancelled { return }
        var fileResults: [SearchFileResult] = []
        for (i, file) in allProjectFiles.enumerated() {
            if Task.isCancelled { return }
            if i % 200 == 0 { await Task.yield() }
            guard file.fileName.lowercased().contains(q) else { continue }
            fileResults.append(SearchFileResult(
                id: file.id,
                name: file.fileName,
                url: file.localURL,
                subtitle: t("search.sectionProjects"),
                icon: file.fileIcon,
                iconColor: colorFromName(file.fileIconColorName)
            ))
        }
        for (i, receipt) in allReceiptAttachments.enumerated() {
            if Task.isCancelled { return }
            if i % 200 == 0 { await Task.yield() }
            guard receipt.fileName.lowercased().contains(q) else { continue }
            fileResults.append(SearchFileResult(
                id: receipt.id,
                name: receipt.fileName,
                url: ReceiptAttachmentStore.fileURL(for: receipt),
                subtitle: receipt.transaction?.placeName ?? t("search.sectionTransactions"),
                icon: receipt.kind == .pdf ? "doc.fill" : "photo.fill",
                iconColor: receipt.kind == .pdf ? .orange : .blue
            ))
        }
        fileResults.sort { $0.name < $1.name }

        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            filteredTransactions = txResults
            filteredCategories   = catResults
            filteredGoals        = goalResults
            filteredProjects     = projectResults
            filteredFiles        = fileResults
            isSearching          = false
        }
    }

    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue":   return .blue
        case "red":    return .red
        case "green":  return .green
        case "orange": return .orange
        case "yellow": return .yellow
        case "purple": return .purple
        case "pink":   return .pink
        default:       return .gray
        }
    }
}

// MARK: - File preview sheet with Close + Share toolbar

private struct SearchFilePreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReceiptPreviewSheet(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .accessibilityLabel(t("common.close"))
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
        }
    }
}
