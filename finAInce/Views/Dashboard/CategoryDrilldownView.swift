import SwiftUI
import SwiftData
import Charts

// MARK: - CategoryMonthPoint

fileprivate struct CategoryMonthPoint: Identifiable {
    let id        = UUID()
    let date:       Date
    let amount:     Double
    let isForecast: Bool
    let isCurrent:  Bool
}

// MARK: - CategoryDrilldownView

struct CategoryDrilldownView: View {
    let category: Category
    let transactions: [Transaction]

    @Environment(\.dismiss) private var dismiss
    @Query private var goals: [Goal]
    @Query private var allTransactions: [Transaction]   // histórico completo para o gráfico
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    @State private var selectedHistoryMonth: Date?  = nil
    @State private var transactionToEdit: Transaction? = nil

    // MARK: - Derived

    var categoryTransactions: [Transaction] {
        transactions.filter {
            $0.type == .expense &&
            ($0.category?.id == category.id || $0.category?.parent?.id == category.id)
        }
        .sorted { $0.date > $1.date }
    }

    var totalAmount: Double {
        categoryTransactions.reduce(0) { $0 + $1.amount }
    }

    var totalPaid: Double {
        categoryTransactions.filter { $0.isPaid }.reduce(0) { $0 + $1.amount }
    }

    /// Goal cujo escopo bate com esta categoria (raiz ou pai)
    var matchingGoal: Goal? {
        goals.first { goal in
            guard let goalCat = goal.category else { return false }
            return goalCat.id == category.id || goalCat.id == category.parent?.id
        }
    }

    // MARK: - Monthly history chart data

    /// Pontos mensais: 3 meses anteriores + mês atual + 3 meses futuros (previsão).
    /// Realizado = dados reais; Previsão = média dos meses realizados.
    fileprivate var categoryMonthlyPoints: [CategoryMonthPoint] {
        let calendar = Calendar.current
        guard let currentStart = calendar.dateInterval(of: .month, for: Date())?.start else { return [] }

        let catTx = allTransactions.filter {
            $0.type == .expense &&
            ($0.category?.id == category.id || $0.category?.parent?.id == category.id)
        }

        var points: [CategoryMonthPoint] = []
        var realizedAmounts: [Double] = []

        for offset in -3...3 {
            guard let monthStart = calendar.date(byAdding: .month, value: offset, to: currentStart) else { continue }
            let isFuture  = offset > 0
            let isCurrent = offset == 0

            if !isFuture {
                let total = catTx
                    .filter { calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month) }
                    .reduce(0.0) { $0 + $1.amount }
                // mostra o mês mesmo com 0 se for o atual; ignora meses passados sem dados
                if total > 0 || isCurrent {
                    points.append(CategoryMonthPoint(
                        date: monthStart, amount: total,
                        isForecast: false, isCurrent: isCurrent
                    ))
                    if !isCurrent && total > 0 { realizedAmounts.append(total) }
                }
            } else {
                // previsão só se houver histórico realizado
                guard !realizedAmounts.isEmpty else { continue }
                let avg = realizedAmounts.reduce(0, +) / Double(realizedAmounts.count)
                points.append(CategoryMonthPoint(
                    date: monthStart, amount: avg,
                    isForecast: true, isCurrent: false
                ))
            }
        }
        return points
    }

    /// Exibe o gráfico apenas se houver pelo menos 2 pontos (1 realizado + atual)
    var shouldShowHistoryChart: Bool { categoryMonthlyPoints.count >= 2 }

    // MARK: - Subcategory grouping

    // Agrupa por subcategoria
    var bySubcategory: [(name: String, total: Double)] {
        var dict: [String: Double] = [:]
        for transaction in categoryTransactions {
            let key = transaction.subcategory?.displayName
                ?? transaction.category?.displayName
                ?? t("insight.fallback.uncategorized")
            dict[key, default: 0] += transaction.amount
        }
        return dict.map { ($0.key, $0.value) }.sorted { $0.total > $1.total }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // ── Cabeçalho da categoria ──
                Section {
                    HStack {
                        Image(systemName: category.icon)
                            .foregroundStyle(Color(hex: category.color))
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(category.displayName).font(.headline)
                            Text(totalAmount.asCurrency(currencyCode))
                                .font(.title2.bold())
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ── Meta associada ──
                if let goal = matchingGoal {
                    goalInsightSection(goal: goal)
                }

                // ── Histórico mensal ──
                if shouldShowHistoryChart {
                    Section {
                        categoryHistoryChart
                            .padding(.vertical, 6)
                    } header: {
                        Text(t("dashboard.monthlyHistory"))
                    }
                }

                // ── Por subcategoria ──
                if !bySubcategory.isEmpty {
                    Section(t("dashboard.bySub")) {
                        ForEach(bySubcategory, id: \.name) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(item.total.asCurrency(currencyCode))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // ── Transações ──
                Section(t("dashboard.transactions")) {
                    ForEach(categoryTransactions) { transaction in
                        TransactionRowView(transaction: transaction)
                            .onTapGesture { transactionToEdit = transaction }
                    }
                }
            }
            .navigationTitle(category.displayName)
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

    // MARK: - Category History Chart

    private var categoryHistoryChart: some View {
        let points        = categoryMonthlyPoints
        let historical    = points.filter { !$0.isForecast }
        let forecast      = points.filter { $0.isCurrent || $0.isForecast }
        let current       = points.first  { $0.isCurrent }
        let previous      = points.last   { !$0.isForecast && !$0.isCurrent }
        let selectedPoint = selectedCategoryHistoryPoint(in: points) ?? current

        let amounts  = points.map(\.amount)
        let padding  = (amounts.max() ?? 1) * 0.18
        let yMin     = max(0, (amounts.min() ?? 0) - padding)
        let yMax     = (amounts.max() ?? 1) + padding * 3.2

        let delta: Double? = {
            guard let c = current, let p = previous, p.amount > 0 else { return nil }
            return (c.amount - p.amount) / p.amount * 100
        }()

        return VStack(alignment: .leading, spacing: 14) {
            // Cabeçalho
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("dashboard.lastMonthsForecast"))
                        .font(.subheadline.weight(.semibold))
                    if let delta {
                        let sign: String = delta >= 0 ? "+" : ""
                        let color: Color = delta > 2 ? .red : delta < -2 ? .green : .secondary
                        Text(t("transaction.vsPreviousMonth", "\(sign)\(String(format: "%.0f", delta))"))
                            .font(.caption)
                            .foregroundStyle(color)
                    } else {
                        Text(t("dashboard.monthlySpendTotal"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    categoryLegendItem(color: .green,  dashed: false, label: t("dashboard.done"))
                    categoryLegendItem(color: .orange, dashed: true,  label: t("dashboard.forecast"))
                }
            }

            Chart {
                // Área sob histórico
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

                // Linha previsão — pontilhada, azul suave
                ForEach(forecast) { point in
                    LineMark(
                        x: .value("Mês", point.date),
                        y: .value("Valor", point.amount)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 5]))
                }

                // Pontos — verde realizado, laranja previsão
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
                        position: categoryAnnotationPosition(for: sel, in: points),
                        alignment: .center
                    ) {
                        categoryTooltip(for: sel)
                    }
                }
            }
            .frame(height: 160)
            .chartYScale(domain: yMin...yMax)
            .chartYAxis(.hidden)
            .chartXScale(range: .plotDimension(padding: 20))
            .chartXAxis {
                AxisMarks(values: points.map(\.date)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            let isCur = points.first(where: {
                                Calendar.current.isDate($0.date, equalTo: date, toGranularity: .month)
                            })?.isCurrent == true
                            Text(categoryMonthLabel(date))
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
                                .onChanged { value in
                                    selectNearestCategoryPoint(
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
    }

    // MARK: - Chart helpers

    @ViewBuilder
    private func categoryTooltip(for point: CategoryMonthPoint) -> some View {
        VStack(spacing: 2) {
            Text(categoryMonthLabel(point.date, wide: true))
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
    private func categoryLegendItem(color: Color, dashed: Bool, label: String) -> some View {
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

    private func categoryAnnotationPosition(
        for point: CategoryMonthPoint,
        in points: [CategoryMonthPoint]
    ) -> AnnotationPosition {
        guard let idx = points.firstIndex(where: { $0.id == point.id }) else { return .top }
        if idx == 0                { return .topTrailing }
        if idx == points.count - 1 { return .topLeading }
        return .top
    }

    private func selectedCategoryHistoryPoint(in points: [CategoryMonthPoint]) -> CategoryMonthPoint? {
        guard let sel = selectedHistoryMonth else { return nil }
        return points.first {
            Calendar.current.isDate($0.date, equalTo: sel, toGranularity: .month)
        }
    }

    private func selectNearestCategoryPoint(
        to location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [CategoryMonthPoint]
    ) {
        guard let plotFrameAnchor = proxy.plotFrame else { return }
        let plotFrame = geometry[plotFrameAnchor]
        guard plotFrame.contains(location) else { return }
        let xPosition = location.x - plotFrame.origin.x
        guard let tappedDate: Date = proxy.value(atX: xPosition) else { return }
        selectedHistoryMonth = points.min {
            abs($0.date.timeIntervalSince(tappedDate)) < abs($1.date.timeIntervalSince(tappedDate))
        }?.date
    }

    private func categoryMonthLabel(_ date: Date, wide: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = wide ? "LLLL yyyy" : "LLL"
        return f.string(from: date).capitalized
    }

    // MARK: - Goal Insight Section

    @ViewBuilder
    private func goalInsightSection(goal: Goal) -> some View {
        let target   = goal.targetAmount
        let forecast = totalAmount          // pago + pendente da categoria no mês
        let paid     = totalPaid
        let pct      = target > 0 ? Int((forecast / target * 100).rounded()) : 0
        let remaining = max(0, target - forecast)

        let statusColor: Color = {
            switch pct {
            case ..<75:  return .green
            case 75..<90: return .orange
            default:      return .red
            }
        }()

        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Header da meta
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(statusColor.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: goal.iconName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(statusColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title)
                            .font(.subheadline.weight(.semibold))
                        Text(t("goal.monthGoal"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(pct)%")
                            .font(.subheadline.bold())
                            .foregroundStyle(statusColor)
                        Text(t("goal.ofAmount", target.asCurrency(currencyCode)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Barra de progresso dupla (pago sólido + previsto suave)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemFill))
                            .frame(height: 10)

                        // Previsto (mais claro)
                        if target > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(statusColor.opacity(0.3))
                                .frame(
                                    width: geo.size.width * min(forecast / target, 1.0),
                                    height: 10
                                )
                                .animation(.easeOut(duration: 0.5), value: forecast)
                        }

                        // Pago (sólido)
                        if target > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(statusColor)
                                .frame(
                                    width: geo.size.width * min(paid / target, 1.0),
                                    height: 10
                                )
                                .animation(.easeOut(duration: 0.5), value: paid)
                        }
                    }
                }
                .frame(height: 10)

                // Números e status
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label {
                            Text(t("goal.paidAmount", paid.asCurrency(currencyCode)))
                                .font(.caption)
                        } icon: {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 7, height: 7)
                        }

                        if forecast > paid {
                            Label {
                                Text(t("goal.expectedAmount", forecast.asCurrency(currencyCode)))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } icon: {
                                Circle()
                                    .fill(statusColor.opacity(0.35))
                                    .frame(width: 7, height: 7)
                            }
                        }

                        if remaining > 0 {
                            Text(t("goal.availableAmount", remaining.asCurrency(currencyCode)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Status chip
                    Text(pct < 75 ? t("goal.status.within")
                         : pct < 100 ? t("goal.status.nearLimit")
                         : t("goal.status.overLimit"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text(t("goal.categoryGoal"))
        }
    }
}
