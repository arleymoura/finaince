import SwiftUI

struct MonthComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MonthComparisonViewModel

    init(
        transactions: [Transaction],
        goals: [Goal],
        currencyCode: String,
        aiSettings: AISettings?,
        selectedAccountId: UUID? = nil,
        initialMonthA: MonthReference? = nil,
        initialMonthB: MonthReference? = nil
    ) {
        _viewModel = State(
            initialValue: MonthComparisonViewModel(
                transactions: transactions,
                goals: goals,
                currencyCode: currencyCode,
                aiSettings: aiSettings,
                selectedAccountId: selectedAccountId,
                initialMonthA: initialMonthA,
                initialMonthB: initialMonthB
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    if let result = viewModel.result {
                        summaryCard(result)
                        aiInsightSection
                        categorySection(result)
                        highlightsSection(result)
                        behaviorSection(result)
                        exportSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(WorkspaceBackground(isRegularLayout: false).ignoresSafeArea())
            .navigationTitle(t("monthComparator.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.close")) { dismiss() }
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("monthComparator.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                monthPicker(title: t("monthComparator.baseMonth"), selection: $viewModel.monthA)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 22)
                monthPicker(title: t("monthComparator.compareMonth"), selection: $viewModel.monthB)
            }
        }
    }

    private func monthPicker(title: String, selection: Binding<MonthReference>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(title, selection: selection) {
                ForEach(viewModel.availableMonths, id: \.self) { month in
                    Text(month.title())
                        .tag(month)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .onChange(of: selection.wrappedValue) { _, _ in
            Task { await viewModel.monthChanged() }
        }
    }

    private func summaryCard(_ result: MonthComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: t("monthComparator.summary"),
                systemImage: "chart.bar.doc.horizontal"
            )

            HStack(spacing: 12) {
                summaryMetric(title: result.monthA.title(), value: result.summary.totalA.asCurrency(viewModel.currencyCode))
                summaryMetric(title: result.monthB.title(), value: result.summary.totalB.asCurrency(viewModel.currencyCode))
            }

            HStack(spacing: 12) {
                summaryMetric(
                    title: t("monthComparator.goalLabel"),
                    value: result.summary.goalTotalA.asCurrency(viewModel.currencyCode)
                )
                summaryMetric(
                    title: t("monthComparator.goalLabel"),
                    value: result.summary.goalTotalB.asCurrency(viewModel.currencyCode)
                )
            }

            HStack(spacing: 10) {
                Image(systemName: result.summary.difference > 0 ? "arrow.up.right" : result.summary.difference < 0 ? "arrow.down.right" : "equal")
                    .font(.subheadline.bold())
                Text(result.summary.difference.asCurrency(viewModel.currencyCode))
                    .font(.title3.bold())
                Text("\(Int(result.summary.percentageChange.rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(viewModel.summaryTrendColor.opacity(0.12), in: Capsule())
            }
            .foregroundStyle(viewModel.summaryTrendColor)
        }
        .dashboardStyleCard()
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func categorySection(_ result: MonthComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: t("monthComparator.categoryImpact"),
                systemImage: "arrow.left.arrow.right.square"
            )

            ForEach(result.categories) { category in
                categoryRow(category, result: result)

                if category.id != result.categories.last?.id {
                    Divider()
                }
            }
        }
        .dashboardStyleCard()
    }

    private func categoryRow(_ category: MonthComparisonCategory, result: MonthComparisonResult) -> some View {
        let presentation = viewModel.presentation(for: category.name)
        let trendColor = color(for: category.trend)
        let maxValue = max(category.totalA, category.totalB, 1)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(presentation.color.opacity(0.14))
                        .frame(width: 44, height: 44)

                    Image(systemName: presentation.icon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(presentation.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(category.name)
                            .font(.subheadline.weight(.semibold))

                        trendBadge(category.trend)
                    }

                    Text(trendSummary(category))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let goalA = category.goalA ?? category.goalB, goalA > 0 {
                        Text(t("monthComparator.goalValue", goalA.asCurrency(viewModel.currencyCode)))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(category.difference.asCurrency(viewModel.currencyCode))
                        .font(.subheadline.bold())
                        .foregroundStyle(trendColor)
                    Text("\(Int(category.percentageChange.rounded()))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trendColor)
                }
            }

            VStack(spacing: 10) {
                comparisonBar(
                    title: result.monthA.title(),
                    value: category.totalA,
                    maxValue: maxValue,
                    tint: presentation.color.opacity(0.45)
                )
                comparisonBar(
                    title: result.monthB.title(),
                    value: category.totalB,
                    maxValue: maxValue,
                    tint: presentation.color
                )
            }
        }
        .padding(.vertical, 6)
    }

    private func highlightsSection(_ result: MonthComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: t("monthComparator.highlights"),
                systemImage: "sparkles.rectangle.stack"
            )

            highlightBlock(title: t("monthComparator.biggestIncrease"), items: result.highlights.biggestIncrease, color: .red)
            highlightBlock(title: t("monthComparator.biggestSavings"), items: result.highlights.biggestDecrease, color: .green)
            highlightBlock(title: t("monthComparator.newExpenses"), items: result.highlights.newCategories, color: .orange)
        }
        .dashboardStyleCard()
    }

    private func highlightBlock(title: String, items: [MonthComparisonHighlightItem], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if items.isEmpty {
                Text(t("monthComparator.none"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HStack {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                        Text(item.name)
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(item.difference.asCurrency(viewModel.currencyCode))
                            .font(.caption.bold())
                            .foregroundStyle(color)
                    }
                }
            }
        }
    }

    private func behaviorSection(_ result: MonthComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: t("monthComparator.behavior"),
                systemImage: "calendar.badge.clock"
            )

            VStack(alignment: .leading, spacing: 10) {
                behaviorRow(
                    title: t("monthComparator.avgDaily"),
                    leftValue: result.behavior.avgDailyA.asCurrency(viewModel.currencyCode),
                    rightValue: result.behavior.avgDailyB.asCurrency(viewModel.currencyCode)
                )
                behaviorRow(
                    title: t("monthComparator.peakDay"),
                    leftValue: "\(result.behavior.peakDayA.label) • \(result.behavior.peakDayA.total.asCurrency(viewModel.currencyCode))",
                    rightValue: "\(result.behavior.peakDayB.label) • \(result.behavior.peakDayB.total.asCurrency(viewModel.currencyCode))"
                )
                behaviorRow(
                    title: t("monthComparator.distribution"),
                    leftValue: distributionLabel(result.behavior.distributionA),
                    rightValue: distributionLabel(result.behavior.distributionB)
                )
            }
        }
        .dashboardStyleCard()
    }

    private func comparisonBar(title: String, value: Double, maxValue: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value.asCurrency(viewModel.currencyCode))
                    .font(.caption.weight(.semibold))
            }

            GeometryReader { proxy in
                let width = maxValue > 0 ? max(10, proxy.size.width * (value / maxValue)) : 10

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 999)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.72), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func behaviorRow(title: String, leftValue: String, rightValue: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                behaviorPill(title: viewModel.monthA.title(), value: leftValue)
                behaviorPill(title: viewModel.monthB.title(), value: rightValue)
            }
        }
    }

    private func behaviorPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var aiInsightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.14))
                            .frame(width: 34, height: 34)

                        Image(systemName: "sparkles")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.purple)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("IA")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.purple)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text(t("monthComparator.aiTitle"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
                Spacer()
                if viewModel.isLoadingAIInsight {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(viewModel.aiInsight)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.10),
                    Color.purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.purple.opacity(0.14), lineWidth: 1)
        )
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 16) {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        exportHeroIcon(systemName: "doc.text.fill")
                        exportHeroIcon(systemName: "paperplane.fill")
                        exportHeroIcon(systemName: "sparkles")
                    }

                    VStack(spacing: 6) {
                        Text(t("monthComparator.exportTitle"))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text(t("monthComparator.exportSubtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.blue.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 0) {
                    exportStepRow(
                        number: 1,
                        icon: "doc.text.fill",
                        text: t("transaction.aiAnalysisStep1")
                    )
                    exportStepConnector
                    exportStepRow(
                        number: 2,
                        icon: "paperplane.fill",
                        text: t("transaction.aiAnalysisStep2")
                    )
                    exportStepConnector
                    exportStepRow(
                        number: 3,
                        icon: "lightbulb.fill",
                        text: t("transaction.aiAnalysisStep3")
                    )
                }
                .padding(.vertical, 4)

                if let exportURL = viewModel.exportURL {
                    ShareLink(item: exportURL) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline.weight(.bold))
                            Text(t("monthComparator.exportCTA"))
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if let exportErrorMessage = viewModel.exportErrorMessage {
                    Text(exportErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .dashboardStyleCard()
    }

    private func exportHeroIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    )
            )
    }

    private func exportStepRow(number: Int, icon: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 32, height: 32)

                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }

            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }

    private var exportStepConnector: some View {
        HStack {
            Rectangle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 2, height: 12)
                .padding(.leading, 19)
            Spacer()
        }
    }

    private func color(for trend: MonthComparisonTrend) -> Color {
        switch trend {
        case .increase: return .red
        case .decrease: return .green
        case .stable: return .secondary
        }
    }

    private func trendBadge(_ trend: MonthComparisonTrend) -> some View {
        Text(trendLabel(trend))
            .font(.caption2.weight(.bold))
            .foregroundStyle(color(for: trend))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color(for: trend).opacity(0.12), in: Capsule())
    }

    private func trendLabel(_ trend: MonthComparisonTrend) -> String {
        switch trend {
        case .increase:
            return t("monthComparator.trendIncrease")
        case .decrease:
            return t("monthComparator.trendDecrease")
        case .stable:
            return t("monthComparator.trendStable")
        }
    }

    private func trendSummary(_ category: MonthComparisonCategory) -> String {
        "\(viewModel.monthA.title()) \(category.totalA.asCurrency(viewModel.currencyCode)) • \(viewModel.monthB.title()) \(category.totalB.asCurrency(viewModel.currencyCode))"
    }

    private func distributionLabel(_ distribution: MonthSpendingDistribution) -> String {
        switch distribution.dominantSegment {
        case "early":
            return t("monthComparator.distributionEarly")
        case "late":
            return t("monthComparator.distributionLate")
        default:
            return t("monthComparator.distributionMid")
        }
    }

    private func sectionHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
        }
    }
}

private extension View {
    func dashboardStyleCard() -> some View {
        self
            .padding(18)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 14, y: 6)
    }
}
