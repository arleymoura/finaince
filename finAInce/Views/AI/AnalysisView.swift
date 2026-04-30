import SwiftUI
import SwiftData

struct AnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [Transaction]
    @Query private var analyses: [AIAnalysis]

    @State private var selectedMonth = Calendar.current.component(.month, from: Date())
    @State private var selectedYear  = Calendar.current.component(.year,  from: Date())
    @State private var isLoading = false

    var monthRef: String {
        String(format: "%04d-%02d", selectedYear, selectedMonth)
    }

    var currentAnalysis: AIAnalysis? {
        analyses.first { $0.monthRef == monthRef }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthSelectorView(month: $selectedMonth, year: $selectedYear)

                    if isLoading {
                        loadingView
                    } else if let analysis = currentAnalysis {
                        analysisContent(analysis)
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .navigationTitle(t("ai.analysisTitle"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { generateAnalysis() } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                    }
                    .disabled(isLoading)
                }
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(t("ai.analyzing"))
                .font(.subheadline)
                .foregroundStyle(FinAInceColor.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func analysisContent(_ analysis: AIAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(t("ai.generatedByProvider", analysis.provider), systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(FinAInceColor.secondaryText)
                Spacer()
                Text(analysis.generatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(FinAInceColor.secondaryText)
            }

            // Renderiza o conteúdo markdown
            Text(analysis.content)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .finElevatedSurface(cornerRadius: 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                .font(.system(size: 56))
                .foregroundStyle(FinAInceColor.secondaryText)
            Text(t("ai.noAnalysis"))
                .font(.headline)
                .foregroundStyle(FinAInceColor.primaryText)
            Text(t("ai.noAnalysisDesc"))
                .font(.subheadline)
                .foregroundStyle(FinAInceColor.secondaryText)
                .multilineTextAlignment(.center)
            Button(t("ai.generate")) {
                generateAnalysis()
            }
            .buttonStyle(FinPrimaryButtonStyle())
        }
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func generateAnalysis() {
        isLoading = true
        // Sprint 4: substituir por chamada real à AIService
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let placeholder = AIAnalysis(
                monthRef: monthRef,
                provider: t("ai.pendingConfiguration"),
                type: .monthlySummary,
                content: t("ai.configureForAutomaticAnalysis")
            )
            modelContext.insert(placeholder)
            isLoading = false
        }
    }
}
