import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct Step4DetailsView: View {
    @Bindable var state: NewTransactionState
    let onBack: () -> Void
    let onSave: () -> Void

    @Query private var accounts: [Account]
    @Query private var costCenters: [CostCenter]
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    @State private var showAmountEditor    = false
    @State private var showCategoryPicker  = false
    @State private var showProjectPicker   = false
    @State private var showReceiptCamera   = false
    @State private var showReceiptLibrary  = false
    @State private var showReceiptPDFPicker = false
    @State private var previewURL: URL?

    var defaultAccount: Account? {
        accounts.first { $0.isDefault } ?? accounts.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── Seção 1: Transação ─────────────────────────────────────
                formCard {
//                    typeRow
//                    Divider().padding(.leading, 56)
                    amountRow
                    Divider().padding(.leading, 56)
                    placeRow
                }

                // ── Seção 2: Categoria ─────────────────────────────────────
                formCard {
                    categoryRow
                    if !costCenters.filter(\.isActive).isEmpty {
                        Divider().padding(.leading, 56)
                        projectRow
                    }
                }

                // ── Seção 3: Conta & Detalhes ──────────────────────────────
                formCard {
                    accountRow
                    Divider().padding(.leading, 56)
                    dateRow
                    Divider().padding(.leading, 56)
                    recurrenceRow
                    if state.recurrenceType == .installment {
                        Divider().padding(.leading, 56)
                        installmentRow
                    }
                    if state.recurrenceType == .monthly || state.recurrenceType == .annual {
                        Divider().padding(.leading, 56)
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                                .frame(width: 32)
                            Text(state.recurrenceType == .annual
                                 ? t("newTx.annualNote")
                                 : t("newTx.installmentsNote"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    Divider().padding(.leading, 56)
                    notesRow
                    Divider().padding(.leading, 56)
                    paidRow
                }

                formCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "paperclip")
                                .foregroundStyle(.secondary)
                                .frame(width: 32)
                            Text(t("receipt.attachments"))
                                .font(.body.weight(.medium))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                        ReceiptAttachmentSourceBar(
                            onCamera: { showReceiptCamera = true },
                            onGallery: { showReceiptLibrary = true },
                            onPDF: { showReceiptPDFPicker = true }
                        )
                        .padding(.horizontal, 16)

                        if state.receiptDrafts.isEmpty {
                            Text(t("receipt.noAttachments"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 14)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(state.receiptDrafts.enumerated()), id: \.element.id) { index, draft in
                                    ReceiptAttachmentRow(
                                        name: draft.fileName,
                                        kind: draft.kind,
                                        onPreview: { previewURL = draft.localURL },
                                        onRemove: { removeDraft(draft) }
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)

                                    if index < state.receiptDrafts.count - 1 {
                                        Divider().padding(.leading, 56)
                                    }
                                }
                            }
                            .padding(.bottom, 4)
                        }
                    }
                }

                // ── Navegação final ────────────────────────────────────────
                HStack(spacing: 12) {
                    Button(action: onBack) {
                        Text(t("common.back"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Button(action: onSave) {
                        Label(t("transaction.save"), systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear {
            if state.account == nil {
                state.account = defaultAccount
            }
        }
        // Limpa categoria se o tipo mudar para transferência (sem categorias)
        .onChange(of: state.type) { _, newType in
            if newType == .transfer {
                state.category    = nil
                state.subcategory = nil
            }
        }
        .sheet(isPresented: $showAmountEditor) {
            AmountEditorSheet(amount: $state.amount, currencyCode: currencyCode)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(
                selectedCategory:    $state.category,
                selectedSubcategory: $state.subcategory,
                transactionType:     state.type
            )
        }
        .sheet(isPresented: $showReceiptCamera) {
            ImagePickerView(sourceType: .camera) { image in
                appendDraft(from: image)
            }
        }
        .sheet(isPresented: $showReceiptLibrary) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                appendDraft(from: image)
            }
        }
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let previewURL {
                ReceiptPreviewSheet(url: previewURL)
            }
        }
        .fileImporter(
            isPresented: $showReceiptPDFPicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            urls.forEach(appendDraft(from:))
        }
        .navigationTitle(t("newTx.step4"))
    }

    // MARK: - Card helper

    @ViewBuilder
    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Seção Transação

    private var typeRow: some View {
        DetailRow(
            icon: state.type == .expense ? "arrow.down.circle.fill" : "arrow.left.arrow.right.circle.fill",
            label: t("newTx.type")
        ) {
            Picker(t("newTx.type"), selection: $state.type) {
                ForEach(TransactionType.allCases, id: \.self) { t in
                    Text(t.label).tag(t)
                }
            }
            .labelsHidden()
        }
    }

    private var amountRow: some View {
        Button { showAmountEditor = true } label: {
            DetailRow(
                icon: "banknote.fill",
                label: t("transaction.amount"),
                labelFont: .body.weight(.medium),
                contentFont: .body
            ) {
                HStack(spacing: 4) {
                    Text(state.amount.asCurrency(currencyCode))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(state.type == .expense ? .red : .blue)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var placeRow: some View {
        DetailRow(
            icon: "mappin.circle.fill",
            label: t("transaction.establishment"),
            labelFont: .body.weight(.medium),
            contentFont: .body
        ) {
            TextField(t("common.optional"), text: $state.placeName)
                .font(.body)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Seção Categoria

    private var categoryRow: some View {
        Button { showCategoryPicker = true } label: {
            DetailRow(
                icon: state.category?.icon ?? "tag.fill",
                label: t("transaction.category"),
                labelFont: .body.weight(.medium),
                contentFont: .body
            ) {
                HStack(spacing: 6) {
                    if let cat = state.category {
                        Image(systemName: cat.icon)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: cat.color))
                            .frame(width: 22, height: 22)
                            .background(Color(hex: cat.color).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(cat.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            if let sub = state.subcategory {
                                Text(sub.displayName)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text(state.type == .transfer ? t("newTx.naCategory") : t("newTx.selectCategory"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(state.type == .transfer)
    }

    // MARK: - Project Row

    private var projectRow: some View {
        Button { showProjectPicker = true } label: {
            DetailRow(
                icon: state.costCenter?.icon ?? "folder",
                label: t("projects.section"),
                labelFont: .body.weight(.medium),
                contentFont: .body
            ) {
                HStack(spacing: 6) {
                    if let cc = state.costCenter {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: cc.color).opacity(0.15))
                                .frame(width: 22, height: 22)
                            Image(systemName: cc.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(hex: cc.color))
                        }
                        Text(cc.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } else {
                        Text(t("projects.noProject"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showProjectPicker) {
            ProjectPickerSheet(selectedCostCenter: $state.costCenter)
        }
    }

    // MARK: - Seção Detalhes

    private var accountRow: some View {
        DetailRow(
            icon: "creditcard.fill",
            label: t("transaction.account"),
            labelFont: .body.weight(.medium),
            contentFont: .body
        ) {
            Picker(t("transaction.account"), selection: $state.account) {
                Text(t("common.none")).tag(Account?.none)
                ForEach(accounts) { account in
                    Label(account.name, systemImage: account.icon).tag(Account?.some(account))
                }
            }
            .font(.body)
            .labelsHidden()
        }
    }

    private var dateRow: some View {
        DetailRow(
            icon: "calendar",
            label: t("transaction.date"),
            labelFont: .body.weight(.medium),
            contentFont: .body
        ) {
            DatePicker("", selection: $state.date, displayedComponents: .date)
                .font(.body)
                .labelsHidden()
        }
    }

    private var recurrenceRow: some View {
        DetailRow(
            icon: "repeat",
            label: t("newTx.recurrence"),
            labelFont: .body.weight(.medium),
            contentFont: .body
        ) {
            Picker(t("newTx.recurrence"), selection: $state.recurrenceType) {
                ForEach(RecurrenceType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
            .font(.body)
            .labelsHidden()
        }
    }

    private var installmentRow: some View {
        DetailRow(
            icon: "square.stack.fill",
            label: t("newTx.installments"),
            labelFont: .body.weight(.medium),
            contentFont: .body
        ) {
            Stepper("\(state.installmentTotal)x",
                    value: $state.installmentTotal,
                    in: 2...48)
                .font(.body)
                .fixedSize()
        }
    }

    private var notesRow: some View {
        DetailRow(
            icon: "note.text",
            label: t("transaction.notes"),
            labelFont: .body.weight(.medium),
            contentFont: .body
        ) {
            TextField(t("common.optional"), text: $state.notes)
                .font(.body)
                .multilineTextAlignment(.trailing)
        }
    }

    private var paidRow: some View {
        DetailRow(
            icon: state.isPaid ? "checkmark.circle.fill" : "clock.fill",
            label: t("transaction.paid"),
            labelFont: .body.weight(.medium),
            contentFont: .body
        ) {
            Toggle("", isOn: $state.isPaid)
                .labelsHidden()
                .tint(.green)
        }
    }

    private func appendDraft(from image: UIImage) {
        guard let draft = try? ReceiptAttachmentStore.createDraft(from: image) else { return }
        state.receiptDrafts.append(draft)
    }

    private func appendDraft(from url: URL) {
        guard let draft = try? ReceiptAttachmentStore.createDraft(from: url) else { return }
        state.receiptDrafts.append(draft)
    }

    private func removeDraft(_ draft: ReceiptDraftAttachment) {
        state.receiptDrafts.removeAll { $0.id == draft.id }
        ReceiptAttachmentStore.cleanupDraft(draft)
    }
}

// MARK: - Detail Row

struct DetailRow<Content: View>: View {
    let icon: String
    let label: String
    let labelFont: Font
    let contentFont: Font
    @ViewBuilder let content: () -> Content

    init(
        icon: String,
        label: String,
        labelFont: Font = .subheadline.weight(.medium),
        contentFont: Font = .subheadline,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.label = label
        self.labelFont = labelFont
        self.contentFont = contentFont
        self.content = content
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            Text(label)
                .font(labelFont)
                .frame(minWidth: 88, alignment: .leading)

            content()
                .font(contentFont)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Amount Editor Sheet

struct AmountEditorSheet: View {
    @Binding var amount: Double
    let currencyCode: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Text(amount.asCurrency(currencyCode))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(amount > 0 ? .primary : Color(.systemGray3))
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                CentsKeypad(amount: $amount)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle(t("newTx.amountTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.ok")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Category Picker Sheet

struct CategoryPickerSheet: View {
    @Binding var selectedCategory:    Category?
    @Binding var selectedSubcategory: Category?
    let transactionType: TransactionType

    @Environment(\.dismiss) private var dismiss
    @Query private var allCategories: [Category]
    @State private var expandedCategory:   Category?
    @State private var showNewCatForm    = false
    @State private var showNewSubForm    = false

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

    private var rootCategories: [Category] {
        allCategories
            .filter { $0.parent == nil }
            .filter {
                switch transactionType {
                case .expense:  return $0.type == .expense || $0.type == .both
                case .transfer: return false
                }
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Grade de categorias raiz
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(rootCategories) { cat in
                            CategoryGridItem(
                                category: cat,
                                isSelected: selectedCategory?.id == cat.id
                            )
                            .onTapGesture {
                                withAnimation {
                                    selectedCategory    = cat
                                    selectedSubcategory = nil
                                    expandedCategory    = cat
                                }
                            }
                        }

                        // Célula "Nova Categoria"
                        AddCategoryCell(label: t("newTx.newCategoryCell"))
                            .onTapGesture { showNewCatForm = true }
                    }
                    .padding(.horizontal)

                    // Subcategorias da categoria expandida
                    if let expanded = expandedCategory {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t("transaction.subcategory"))
                                .font(.headline)
                                .padding(.horizontal)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(
                                    (expanded.subcategories ?? []).sorted { $0.sortOrder < $1.sortOrder }
                                ) { sub in
                                    CategoryGridItem(
                                        category: sub,
                                        isSelected: selectedSubcategory?.id == sub.id,
                                        isSmall: true
                                    )
                                    .onTapGesture {
                                        withAnimation { selectedSubcategory = sub }
                                    }
                                }

                                // Célula "Nova Subcategoria"
                                AddCategoryCell(isSmall: true, label: t("newTx.newCategoryCell"))
                                    .onTapGesture { showNewSubForm = true }
                            }
                            .padding(.horizontal)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut, value: expandedCategory?.id)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(t("newTx.categoryTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.ok")) { dismiss() }
                        .fontWeight(.semibold)
                        .disabled(selectedCategory == nil)
                }
            }
        }
        .onAppear {
            // Pré-expande a categoria já selecionada
            if let cat = selectedCategory {
                expandedCategory = cat
            }
        }
        // Sheet: nova categoria raiz
        .sheet(isPresented: $showNewCatForm) {
            CategoryFormView { newCat in
                withAnimation {
                    selectedCategory    = newCat
                    selectedSubcategory = nil
                    expandedCategory    = newCat
                }
            }
        }
        // Sheet: nova subcategoria do pai expandido
        .sheet(isPresented: $showNewSubForm) {
            if let parent = expandedCategory {
                CategoryFormView(parent: parent) { newSub in
                    withAnimation { selectedSubcategory = newSub }
                }
            }
        }
    }
}
