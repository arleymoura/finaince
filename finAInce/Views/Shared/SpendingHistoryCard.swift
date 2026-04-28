import SwiftUI
import Charts

// MARK: - SpendingHistoryCard
// Self-contained card that shows 3 past months + current + 3 forecast months.
// Extracted from DashboardView so it can be reused in TransactionListView.

struct SpendingHistoryCard: View {
    let transactions: [Transaction]

    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode
    @State private var selectedMonth: Date? = nil

    var body: some View {
        let points = monthlyPoints
        if points.count >= 2 {
            historyCard(points: points)
        }
    }

    // MARK: - Data

    /// 3 past months + current month + up to 3 forecast months.
    private var monthlyPoints: [SpendingMonthPoint] {
        let calendar = Calendar.current
        guard let currentStart = calendar.dateInterval(of: .month, for: Date())?.start else { return [] }

        let expenses = transactions.filter { $0.type == .expense }
        var points: [SpendingMonthPoint] = []
        var realizedAmounts: [Double] = []

        for offset in -3...3 {
            guard let monthStart = calendar.date(byAdding: .month, value: offset, to: currentStart) else { continue }
            let isFuture  = offset > 0
            let isCurrent = offset == 0

            if !isFuture {
                let total = expenses
                    .filter { calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month) }
                    .reduce(0.0) { $0 + $1.amount }
                if total > 0 || isCurrent {
                    points.append(SpendingMonthPoint(date: monthStart, amount: total,
                                                     isForecast: false, isCurrent: isCurrent))
                    if !isCurrent && total > 0 { realizedAmounts.append(total) }
                }
            } else {
                guard !realizedAmounts.isEmpty else { continue }
                let avg = realizedAmounts.reduce(0, +) / Double(realizedAmounts.count)
                points.append(SpendingMonthPoint(date: monthStart, amount: avg,
                                                 isForecast: true, isCurrent: false))
            }
        }
        return points
    }

    // MARK: - Card

    private func historyCard(points: [SpendingMonthPoint]) -> some View {
        let historical    = points.filter { !$0.isForecast }
        let forecast      = points.filter { $0.isCurrent || $0.isForecast }
        let current       = points.first  { $0.isCurrent }
        let previous      = points.last   { !$0.isForecast && !$0.isCurrent }
        let selectedPoint = selectedPoint(in: points) ?? current

        let amounts  = points.map(\.amount)
        let padding  = (amounts.max() ?? 1) * 0.18
        let yMin     = max(0, (amounts.min() ?? 0) - padding)
        let yMax     = (amounts.max() ?? 1) + padding * 3.2

        let delta: Double? = {
            guard let c = current, let p = previous, p.amount > 0 else { return nil }
            return (c.amount - p.amount) / p.amount * 100
        }()

        return VStack(alignment: .leading, spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.subheadline)
                            .foregroundStyle(.teal)
                        Text(t("dashboard.spendingHistory"))
                            .font(.headline)
                    }
                    if let delta {
                        let sign: String = delta >= 0 ? "+" : ""
                        let color: Color = delta > 2 ? .red : delta < -2 ? .green : .secondary
                        Text(t("dashboard.vsPreviousMonthValue", "\(sign)\(String(format: "%.0f", delta))"))
                            .font(.caption)
                            .foregroundStyle(color)
                    } else {
                        Text(t("dashboard.lastMonthsForecast"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    legendItem(color: .green,  dashed: false, label: t("dashboard.done"))
                    legendItem(color: .orange, dashed: true,  label: t("dashboard.forecast"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // ── Chart ─────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 14) {
                Chart {
                    // Area under historical line
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

                    // Historical line — solid
                    ForEach(historical) { point in
                        LineMark(
                            x: .value("Mês", point.date),
                            y: .value("Valor", point.amount)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }

                    // Forecast line — dashed
                    ForEach(forecast) { point in
                        LineMark(
                            x: .value("Mês", point.date),
                            y: .value("Valor", point.amount)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 5]))
                    }

                    // Dots — green = realized, orange = forecast
                    ForEach(points) { point in
                        PointMark(
                            x: .value("Mês", point.date),
                            y: .value("Valor", point.amount)
                        )
                        .symbolSize(point.isCurrent ? 60 : 36)
                        .foregroundStyle(point.isForecast && !point.isCurrent ? Color.orange : Color.green)
                    }

                    // Selected point + tooltip
                    if let sel = selectedPoint {
                        PointMark(
                            x: .value("Mês",   sel.date),
                            y: .value("Valor", sel.amount)
                        )
                        .symbolSize(140)
                        .foregroundStyle(sel.isForecast && !sel.isCurrent ? Color.orange : Color.green)
                        .annotation(
                            position: annotationPosition(for: sel, in: points),
                            alignment: .center
                        ) {
                            tooltip(for: sel)
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
                                Text(monthLabel(date))
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
                                        selectNearest(
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
            .padding(16)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.03), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func tooltip(for point: SpendingMonthPoint) -> some View {
        VStack(spacing: 2) {
            Text(monthLabel(point.date, wide: true))
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
    private func legendItem(color: Color, dashed: Bool, label: String) -> some View {
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

    private func annotationPosition(for point: SpendingMonthPoint,
                                    in points: [SpendingMonthPoint]) -> AnnotationPosition {
        guard let idx = points.firstIndex(where: { $0.id == point.id }) else { return .top }
        if idx == 0                { return .topTrailing }
        if idx == points.count - 1 { return .topLeading }
        return .top
    }

    private func selectedPoint(in points: [SpendingMonthPoint]) -> SpendingMonthPoint? {
        guard let sel = selectedMonth else { return nil }
        return points.first {
            Calendar.current.isDate($0.date, equalTo: sel, toGranularity: .month)
        }
    }

    private func selectNearest(to location: CGPoint,
                               proxy: ChartProxy,
                               geometry: GeometryProxy,
                               points: [SpendingMonthPoint]) {
        guard let plotFrameAnchor = proxy.plotFrame else { return }
        let plotFrame = geometry[plotFrameAnchor]
        guard plotFrame.contains(location) else { return }
        let xPosition = location.x - plotFrame.origin.x
        guard let tappedDate: Date = proxy.value(atX: xPosition) else { return }
        selectedMonth = points.min {
            abs($0.date.timeIntervalSince(tappedDate)) < abs($1.date.timeIntervalSince(tappedDate))
        }?.date
    }

    private func monthLabel(_ date: Date, wide: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = wide ? "LLLL yyyy" : "LLL"
        return f.string(from: date).capitalized
    }
}

// MARK: - SpendingMonthPoint

fileprivate struct SpendingMonthPoint: Identifiable {
    let id        = UUID()
    let date:       Date
    let amount:     Double
    let isForecast: Bool
    let isCurrent:  Bool
}
