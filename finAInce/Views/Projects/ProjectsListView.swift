import SwiftUI
import SwiftData

// MARK: - ProjectsListView

struct ProjectsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CostCenter.createdAt, order: .reverse) private var projects: [CostCenter]
    @Query private var allTransactions: [Transaction]
    @Query private var allFiles: [CostCenterFile]
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    @State private var showInactive   = false
    @State private var showCreateForm = false

    // MARK: - Filtered & sorted

    private var visibleProjects: [CostCenter] {
        projects
            .filter { showInactive ? true : $0.isActive }
            .sorted {
                // Active first, then by latest transaction date
                if $0.isActive != $1.isActive { return $0.isActive }
                return lastActivityDate($0) > lastActivityDate($1)
            }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if visibleProjects.isEmpty && !showInactive {
                emptyState
            } else if visibleProjects.count <= 3 {
                listLayout
            } else {
                gridLayout
            }
        }
        .navigationTitle(t("projects.title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showCreateForm) {
            ProjectFormView()
        }
    }

    // MARK: - Layouts

    private var listLayout: some View {
        List {
            projectRows
            inactiveToggleRow
        }
        .listStyle(.insetGrouped)
    }

    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                spacing: 14
            ) {
                ForEach(visibleProjects) { project in
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
            .padding()

            // Inactive toggle at bottom
            if !showInactive {
                Button {
                    withAnimation { showInactive = true }
                } label: {
                    Text(t("projects.showInactive"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 32)
            }
        }
    }

    @ViewBuilder
    private var projectRows: some View {
        ForEach(visibleProjects) { project in
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
    }

    @ViewBuilder
    private var inactiveToggleRow: some View {
        if !showInactive {
            Button {
                withAnimation { showInactive = true }
            } label: {
                Text(t("projects.showInactive"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(Color.clear)
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showCreateForm = true } label: {
                Image(systemName: "plus")
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            if showInactive {
                Button {
                    withAnimation { showInactive = false }
                } label: {
                    Text(t("projects.hideInactive"))
                        .font(.subheadline)
                }
            }
        }
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
}

// MARK: - List Row

private struct ProjectListRow: View {
    let project: CostCenter
    let spent: Double
    let txCount: Int
    let fileCount: Int
    let currencyCode: String

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: project.color).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: project.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(hex: project.color))
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if !project.isActive {
                        Text(t("projects.inactive"))
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text(spent.asCurrency(currencyCode))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(txCount) \(t("projects.transactions"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if fileCount > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Label("\(fileCount)", systemImage: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Budget bar
                if let budget = project.budget, budget > 0 {
                    let progress = project.budgetProgress(spent: spent)
                    let status   = project.budgetStatus(spent: spent)
                    ProgressView(value: progress)
                        .tint(status.color)
                        .frame(maxWidth: 180)
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

            VStack(spacing: 3) {
                Text(project.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("\(txCount) tx")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !project.isActive {
                Text(t("projects.inactive"))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
