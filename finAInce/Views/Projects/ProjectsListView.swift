import SwiftUI
import SwiftData

// MARK: - ProjectsListView

struct ProjectsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CostCenter.createdAt, order: .reverse) private var projects: [CostCenter]
    @Query private var allTransactions: [Transaction]
    @Query private var allFiles: [CostCenterFile]
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    @State private var showCreateForm = false
    @State private var showInactive   = false

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
            if projects.isEmpty {
                emptyState
            } else if useGridLayout {
                gridLayout
            } else {
                listLayout
            }
        }
        .navigationTitle(t("projects.title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreateForm = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateForm) {
            ProjectFormView()
        }
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
                if !inactiveProjects.isEmpty {
                    projectGridSection(
                        title: t("projects.inactive"),
                        projects: inactiveProjects
                    )
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

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: project.color).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: project.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: project.color))
            }
            .opacity(project.isActive ? 1 : 0.5)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(project.isActive ? .primary : .secondary)

                // Meta row
                HStack(spacing: 4) {
                    Text(spent.asCurrency(currencyCode))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if txCount > 0 {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text("\(txCount) \(t("projects.transactions"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if fileCount > 0 {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Label("\(fileCount)", systemImage: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Budget bar — only when budget is set
                if let budget = project.budget, budget > 0 {
                    let progress = project.budgetProgress(spent: spent)
                    let status   = project.budgetStatus(spent: spent)
                    ProgressView(value: min(progress, 1.0))
                        .tint(status.color)
                        .frame(maxWidth: 160)
                        .scaleEffect(x: 1, y: 0.7, anchor: .center)
                        .padding(.top, 1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
