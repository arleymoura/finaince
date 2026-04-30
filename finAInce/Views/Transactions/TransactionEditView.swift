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
                        TextField("0,00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title3.bold())
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 4)
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
                    ReceiptPreviewSheet(url: previewURL)
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
        tx.category     = selectedCategory
        tx.subcategory  = selectedSubcategory
        tx.notes        = notes.isEmpty ? nil : notes
        tx.costCenterId = selectedCostCenter?.id
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
