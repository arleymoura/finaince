import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - ProjectDetailView

struct ProjectDetailView: View {
    @Bindable var project: CostCenter

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Query private var allTransactions: [Transaction]
    @Query private var allFiles: [CostCenterFile]
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    @State private var showEdit            = false
    @State private var showDeleteAlert     = false
    @State private var showAddFileMenu     = false
    @State private var showCamera          = false
    @State private var showPhotoLibrary    = false
    @State private var showDocumentPicker  = false
    @State private var previewFile: CostCenterFile? = nil

    // MARK: - Derived

    private var transactions: [Transaction] {
        allTransactions
            .filter { $0.costCenterId == project.id }
            .sorted { $0.date > $1.date }
    }

    private var files: [CostCenterFile] {
        allFiles
            .filter { $0.costCenterId == project.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var totalSpent: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }

    private var budgetStatus: CostCenter.BudgetStatus {
        project.budgetStatus(spent: totalSpent)
    }

    // MARK: - Body

    var body: some View {
        List {
            // ── Header card ───────────────────────────────────────────────
            Section {
                projectHeaderCard
                    .listRowBackground(Color.clear)
            }

            // ── Budget ────────────────────────────────────────────────────
            if let budget = project.budget {
                Section(t("projects.budget")) {
                    budgetRow(spent: totalSpent, budget: budget)
                }
            }

            // ── Transactions ──────────────────────────────────────────────
            Section {
                if transactions.isEmpty {
                    Label(t("projects.noTransactions"), systemImage: "tray")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    ForEach(transactions) { tx in
                        NavigationLink {
                            TransactionEditView(transaction: tx)
                        } label: {
                            projectTransactionRow(tx)
                        }
                    }
                }
            } header: {
                HStack {
                    Text(t("projects.transactions"))
                    Spacer()
                    Text("\(transactions.count)")
                        .foregroundStyle(.secondary)
                }
            }

            // ── Files ─────────────────────────────────────────────────────
            Section {
                if files.isEmpty {
                    Label(t("projects.noFiles"), systemImage: "doc")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    ForEach(files) { file in
                        fileRow(file)
                    }
                    .onDelete { indexSet in
                        deleteFiles(at: indexSet)
                    }
                }

                Button {
                    showAddFileMenu = true
                } label: {
                    Label(t("projects.addFile"), systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            } header: {
                HStack {
                    Text(t("projects.files"))
                    Spacer()
                    Text("\(files.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(t("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        withAnimation { project.isActive.toggle() }
                    } label: {
                        Label(
                            project.isActive ? t("projects.deactivate") : t("projects.activate"),
                            systemImage: project.isActive ? "pause.circle" : "play.circle"
                        )
                    }

                    Divider()

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label(t("projects.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            ProjectFormView(project: project)
        }
        .sheet(isPresented: $showCamera) {
            ImagePickerView(sourceType: .camera) { image in
                saveImageFile(image)
            }
        }
        .sheet(isPresented: $showPhotoLibrary) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                saveImageFile(image)
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { url in
                saveDocumentFile(url: url)
            }
        }
        .sheet(item: $previewFile) { file in
            if let url = file.localURL {
                ReceiptPreviewSheet(url: url)
            }
        }
        .confirmationDialog(t("projects.addFile"), isPresented: $showAddFileMenu) {
            Button(t("ai.camera"))    { showCamera = true }
            Button(t("ai.gallery"))   { showPhotoLibrary = true }
            Button(t("projects.addFileDocument")) { showDocumentPicker = true }
            Button(t("common.cancel"), role: .cancel) {}
        }
        .alert(t("projects.deleteConfirm"), isPresented: $showDeleteAlert) {
            Button(t("projects.delete"), role: .destructive) { deleteProject() }
            Button(t("common.cancel"), role: .cancel) {}
        } message: {
            Text(t("projects.deleteWarning"))
        }
    }

    // MARK: - Header Card

    private var projectHeaderCard: some View {
        VStack(spacing: 0) {
            // Top band with gradient
            ZStack {
                LinearGradient(
                    colors: [Color(hex: project.color), Color(hex: project.color).opacity(0.65)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 72, height: 72)
                        Image(systemName: project.icon)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(spacing: 4) {
                        Text(project.name)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        if let desc = project.desc, !desc.isEmpty {
                            Text(desc)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.vertical, 28)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Stats row
            HStack(spacing: 0) {
                statCell(
                    label: t("projects.spent"),
                    value: totalSpent.asCurrency(currencyCode)
                )
                Divider().frame(height: 36)
                statCell(
                    label: t("projects.transactions"),
                    value: "\(transactions.count)"
                )
                Divider().frame(height: 36)
                statCell(
                    label: t("projects.files"),
                    value: "\(files.count)"
                )
            }
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.top, 12)
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Budget Row

    private func budgetRow(spent: Double, budget: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(spent.asCurrency(currencyCode))
                    .font(.headline.bold())
                Text("/ \(budget.asCurrency(currencyCode))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                let status = project.budgetStatus(spent: spent)
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)
            }

            let progress = project.budgetProgress(spent: spent)
            let status   = project.budgetStatus(spent: spent)
            ProgressView(value: progress)
                .tint(status.color)
                .animation(.easeInOut, value: progress)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Transaction Row

    private func projectTransactionRow(_ tx: Transaction) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: tx.category?.color ?? "#8E8E93").opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: tx.category?.icon ?? "creditcard.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: tx.category?.color ?? "#8E8E93"))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.placeName ?? tx.category?.displayName ?? t("transaction.noPlace"))
                    .font(.subheadline)
                    .lineLimit(1)
                Text(tx.date.formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(tx.amount.asCurrency(currencyCode))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - File Row

    private func fileRow(_ file: CostCenterFile) -> some View {
        Button { previewFile = file } label: {
            HStack(spacing: 12) {
                Image(systemName: file.fileIcon)
                    .font(.title3)
                    .foregroundStyle(fileIconColor(for: file))
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text(file.createdAt.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.caption)
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

    private func fileIconColor(for file: CostCenterFile) -> Color {
        switch file.fileIconColorName {
        case "blue":   return .blue
        case "red":    return .red
        case "green":  return .green
        case "orange": return .orange
        case "yellow": return .yellow
        case "purple": return .purple
        case "pink":   return .pink
        default:       return .secondary
        }
    }

    // MARK: - Actions

    private func saveImageFile(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        guard let file = try? CostCenterFile.create(
            forProject: project.id,
            data: data,
            fileType: "jpg",
            ext: "jpg"
        ) else { return }
        modelContext.insert(file)
    }

    private func saveDocumentFile(url: URL) {
        guard let file = try? CostCenterFile.create(
            forProject: project.id,
            copyingFrom: url
        ) else { return }
        modelContext.insert(file)
    }

    private func deleteFiles(at offsets: IndexSet) {
        for index in offsets {
            let file = files[index]
            file.deleteFromDisk()
            modelContext.delete(file)
        }
    }

    private func deleteProject() {
        // 1. Clear costCenterId from all related transactions
        for tx in allTransactions where tx.costCenterId == project.id {
            tx.costCenterId = nil
        }
        // 2. Delete all files from disk + model
        for file in allFiles where file.costCenterId == project.id {
            file.deleteFromDisk()
            modelContext.delete(file)
        }
        // 3. Delete the project itself
        modelContext.delete(project)
        dismiss()
    }
}
