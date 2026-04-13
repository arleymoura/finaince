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
            .navigationTitle("Análise IA")
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
            Text("Analisando seus gastos...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func analysisContent(_ analysis: AIAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Gerado por \(analysis.provider)", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(analysis.generatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Renderiza o conteúdo markdown
            Text(analysis.content)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Nenhuma análise gerada")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Toque no botão acima para gerar uma análise dos seus gastos com IA.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Gerar Análise") {
                generateAnalysis()
            }
            .buttonStyle(.borderedProminent)
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
                provider: "Pendente configuração",
                type: .monthlySummary,
                content: "Configure sua chave de API em **Configurações → IA** para gerar análises automáticas dos seus gastos."
            )
            modelContext.insert(placeholder)
            isLoading = false
        }
    }
}
