import SwiftUI
import SwiftData

// MARK: - ProjectsListView

struct ProjectsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \CostCenter.createdAt, order: .reverse) private var projects: [CostCenter]
    @Query private var allTransactions: [Transaction]
    @Query private var allFiles: [CostCenterFile]
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    @State private var showCreateForm = false
    @State private var showInactive   = false
    private let regularContentMaxWidth: CGFloat = 1100
    private var isRegularLayout: Bool { horizontalSizeClass == .regular }

    // MARK: - Filtered & sorted

    private var activeProjects: [CostCenter] {
        projects
            .filter { $0.isActive }
            .sorted { lastActivityDate($0) > lastActivityDate($1) }
    }

    private var inactiveProjects: [CostCenter] {
        projects
            .filter { !$0.isActive }
            .sorted { lastActivityDate($0) > lastActivityDate($1) }
    }

    private var useGridLayout: Bool {
        projects.filter { $0.isActive }.count > 6
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isRegularLayout {
                regularProjectsView
            } else {
                projectsContent
                    .navigationTitle(t("projects.title"))
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showCreateForm = true } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showCreateForm) {
            ProjectFormView()
                .presentationDetents([.fraction(0.78), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationSizing(.form)
        }
    }

    private var projectsContent: some View {
        Group {
            if projects.isEmpty {
                emptyState
            } else if useGridLayout {
                gridLayout
            } else {
                listLayout
            }
        }
    }

    private var regularProjectsView: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 38, height: 38)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Circle())
                        }

                        Text(t("projects.title"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        Button { showCreateForm = true } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 38, height: 38)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, proxy.safeAreaInsets.top + 18)
                    .padding(.bottom, 18)
                    .frame(maxWidth: regularContentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGroupedBackground))

                    projectsContent
                        .frame(maxWidth: regularContentMaxWidth)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - List Layout

    private var listLayout: some View {
        List {
            // ── Ativos ────────────────────────────────────────────────────
            Section {
                if activeProjects.isEmpty {
                    Text(t("projects.empty.title"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(activeProjects) { project in
                        projectListLink(project)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { deleteProject(project) } label: {
                                    Label(t("common.delete"), systemImage: "trash")
                                }
                                Button { toggleActive(project) } label: {
                                    Label(t("projects.deactivate"), systemImage: "pause.circle")
                                }
                                .tint(.orange)
                            }
                    }
                }
            } header: {
                if !inactiveProjects.isEmpty {
                    Text(t("projects.active"))
                }
            }

            // ── Inativos ──────────────────────────────────────────────────
            if showInactive && !inactiveProjects.isEmpty {
                Section {
                    ForEach(inactiveProjects) { project in
                        projectListLink(project)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { deleteProject(project) } label: {
                                    Label(t("common.delete"), systemImage: "trash")
                                }
                                Button { toggleActive(project) } label: {
                                    Label(t("projects.activate"), systemImage: "play.circle")
                                }
                                .tint(.green)
                            }
                    }
                } header: {
                    Text(t("projects.inactive"))
                }
            }

            // ── Toggle inativos ───────────────────────────────────────────
            if !inactiveProjects.isEmpty {
                Section {
                    Button {
                        withAnimation { showInactive.toggle() }
                    } label: {
                        HStack {
                            Text(showInactive ? t("projects.hideInactive") : t("projects.showInactive"))
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            if !showInactive {
                                Text("\(inactiveProjects.count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private func projectListLink(_ project: CostCenter) -> some View {
        NavigationLink {
            ProjectDetailView(project: project)
        } label: {
            ProjectListRow(
                project: project,
                spent: spent(for: project),
                txCount: transactionCount(for: project),
                fileCount: fileCount(for: project),
                currencyCode: currencyCode
            )
        }
    }

    // MARK: - Grid Layout

    private var gridLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ── Ativos ────────────────────────────────────────────────
                if !activeProjects.isEmpty {
                    projectGridSection(
                        title: inactiveProjects.isEmpty ? nil : t("projects.active"),
                        projects: activeProjects
                    )
                }

                // ── Inativos ──────────────────────────────────────────────
                if showInactive && !inactiveProjects.isEmpty {
                    projectGridSection(
                        title: t("projects.inactive"),
                        projects: inactiveProjects
                    )
                }

                if !inactiveProjects.isEmpty {
                    Button {
                        withAnimation { showInactive.toggle() }
                    } label: {
                        HStack(spacing: 10) {
                            Text(showInactive ? t("projects.hideInactive") : t("projects.showInactive"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)

                            Spacer()

                            if !showInactive {
                                Text("\(inactiveProjects.count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(FinAInceColor.secondaryText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(FinAInceColor.insetSurface)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(FinAInceColor.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(FinAInceColor.borderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func projectGridSection(title: String?, projects: [CostCenter]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                spacing: 14
            ) {
                ForEach(projects) { project in
                    NavigationLink {
                        ProjectDetailView(project: project)
                    } label: {
                        ProjectGridCell(
                            project: project,
                            spent: spent(for: project),
                            txCount: transactionCount(for: project)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 96, height: 96)
                Image(systemName: "folder.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 8) {
                Text(t("projects.empty.title"))
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                Text(t("projects.empty.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                showCreateForm = true
            } label: {
                Label(t("projects.empty.cta"), systemImage: "plus.circle.fill")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private func spent(for project: CostCenter) -> Double {
        allTransactions
            .filter { $0.costCenterId == project.id }
            .reduce(0) { $0 + $1.amount }
    }

    private func transactionCount(for project: CostCenter) -> Int {
        allTransactions.filter { $0.costCenterId == project.id }.count
    }

    private func fileCount(for project: CostCenter) -> Int {
        allFiles.filter { $0.costCenterId == project.id }.count
    }

    private func lastActivityDate(_ project: CostCenter) -> Date {
        allTransactions
            .filter { $0.costCenterId == project.id }
            .map(\.date)
            .max() ?? project.createdAt
    }

    private func toggleActive(_ project: CostCenter) {
        withAnimation { project.isActive.toggle() }
    }

    private func deleteProject(_ project: CostCenter) {
        modelContext.delete(project)
    }
}

// MARK: - List Row

private struct ProjectListRow: View {
    let project: CostCenter
    let spent: Double
    let txCount: Int
    let fileCount: Int
    let currencyCode: String

    private var budget: Double? {
        guard let budget = project.budget, budget > 0 else { return nil }
        return budget
    }

    private var progress: Double? {
        guard budget != nil else { return nil }
        return min(project.budgetProgress(spent: spent), 1.0)
    }

    private var status: (label: String, color: Color)? {
        guard budget != nil else { return nil }
        let budgetStatus = project.budgetStatus(spent: spent)
        let label: String
        switch budgetStatus {
        case .normal:
            label = t("goal.status.good")
        case .warning:
            label = t("goal.status.warning")
        case .critical:
            label = t("goal.status.exceeded")
        case .noBudget:
            label = t("goal.status.great")
        }
        return (label, budgetStatus.color)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: project.color).opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: project.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: project.color))
            }
            .opacity(project.isActive ? 1 : 0.5)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(project.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(project.isActive ? FinAInceColor.primaryText : FinAInceColor.secondaryText)

                    Spacer(minLength: 8)

                    Text(spent.asCurrency(currencyCode))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(FinAInceColor.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                HStack(spacing: 6) {
                    if txCount > 0 {
                        metaChip(label: "\(txCount)", systemImage: "arrow.left.arrow.right")
                    }

                    if fileCount > 0 {
                        metaChip(label: "\(fileCount)", systemImage: "paperclip")
                    }

                    if let budget {
                        metaChip(label: budget.asCurrency(currencyCode), systemImage: "target")
                    }
                }

                if let progress, let status {
                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(FinAInceColor.insetSurface)
                                    .frame(height: 7)
                                Capsule()
                                    .fill(status.color)
                                    .frame(width: geo.size.width * progress, height: 7)
                            }
                        }
                        .frame(height: 7)

                        HStack(spacing: 8) {
                            Text(status.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(status.color)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(FinAInceColor.secondaryText)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func metaChip(label: String, systemImage: String) -> some View {
        Label(label, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(FinAInceColor.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(FinAInceColor.insetSurface)
            .clipShape(Capsule())
    }
}

// MARK: - Grid Cell

private struct ProjectGridCell: View {
    let project: CostCenter
    let spent: Double
    let txCount: Int

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: project.color).opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: project.icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(hex: project.color))
            }
            .opacity(project.isActive ? 1 : 0.5)

            VStack(spacing: 3) {
                Text(project.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(project.isActive ? .primary : .secondary)

                Text("\(txCount) tx")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
