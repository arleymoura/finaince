import SwiftUI
import SwiftData

/// Estado compartilhado entre os 4 steps da nova transação.
@Observable
final class NewTransactionState {
    var amount: Double = 0
    var type: TransactionType = .expense
    var isPaid: Bool = true
    var placeName: String = ""
    var placeGoogleId: String? = nil
    var category: Category? = nil
    var subcategory: Category? = nil
    var account: Account? = nil
    var date: Date = Date()
    var recurrenceType: RecurrenceType = .none
    var installmentTotal: Int = 2
    var notes: String = ""
    var receiptDrafts: [ReceiptDraftAttachment] = []
    var costCenter: CostCenter? = nil
    /// Sinaliza que o fluxo deve pular direto para o step de confirmação (step 4).
    /// Usado pelo scanner de recibos após pré-preencher os dados.
    var jumpToReview: Bool = false
}

struct NewTransactionFlowView: View {
    /// Se `true`, o scanner de recibos abre automaticamente ao entrar no step 1.
    var startWithScanner: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int
    @State private var state: NewTransactionState
    @State private var didSave = false
    @State private var navigationDirection: NavigationDirection = .forward

    /// Inicia o fluxo com estado pré-preenchido e pula direto para a revisão (step 4).
    init(initialState: NewTransactionState, jumpToReview: Bool = true) {
        _state = State(initialValue: initialState)
        _step = State(initialValue: jumpToReview ? 4 : 1)
    }

    /// Inicia o fluxo do zero (behavior padrão).
    init(startWithScanner: Bool = false) {
        self.startWithScanner = startWithScanner
        _state = State(initialValue: NewTransactionState())
        _step = State(initialValue: 1)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Indicador de etapas
                ProgressIndicator(currentStep: step)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Conteúdo do step atual
                Group {
                    switch step {
                    case 1: Step1AmountView(state: state, openScannerOnAppear: startWithScanner)
                    case 2: Step2LocationView(state: state)
                    case 3: Step3CategoryView(state: state)
                    case 4: Step4DetailsView(state: state,
                                             onBack: goBack,
                                             onSave: saveTransaction)
                    default: EmptyView()
                    }
                }
                .transition(contentTransition)
                .animation(.easeInOut(duration: 0.25), value: step)

                // Botões de navegação (exceto Step 4 que tem seu próprio botão Salvar)
                if step < 4 {
                    navigationButtons
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onDisappear {
            if !didSave {
                ReceiptAttachmentStore.cleanupDrafts(state.receiptDrafts)
            }
        }
        // Scanner de recibos pede para pular direto para a confirmação
        .onChange(of: state.jumpToReview) { _, jump in
            guard jump else { return }
            state.jumpToReview = false
            // Pequeno delay para deixar o sheet do scanner fechar antes da transição
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                navigationDirection = .forward
                withAnimation(.easeInOut(duration: 0.25)) { step = 4 }
            }
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if step > 1 {
                Button(action: goBack) { 
                    Text(t("common.back"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            Button(action: goForward) {
                Text(t("common.next"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canAdvance ? Color.accentColor : Color(.systemGray4))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var contentTransition: AnyTransition {
        switch navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return state.amount > 0
        case 2: return true   // local é opcional
        case 3: return state.category != nil
        default: return true
        }
    }

    private func goForward() {
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.25)) {
            step += 1
        }
    }

    private func goBack() {
        navigationDirection = .backward
        withAnimation(.easeInOut(duration: 0.25)) {
            step -= 1
        }
    }

    private var stepTitle: String {
        switch step {
        case 1: return t("newTx.step1")
        case 2: return t("newTx.step2")
        case 3: return t("newTx.step3")
        case 4: return t("newTx.step4")
        default: return ""
        }
    }

    // MARK: - Save

    private func saveTransaction() {
        let transaction = Transaction(
            type: state.type,
            amount: state.amount,
            date: state.date,
            placeName: state.placeName.isEmpty ? nil : state.placeName,
            placeGoogleId: state.placeGoogleId,
            notes: state.notes.isEmpty ? nil : state.notes,
            recurrenceType: state.recurrenceType,
            installmentTotal: state.recurrenceType == .installment ? state.installmentTotal : nil,
            isPaid: state.isPaid
        )
        transaction.account      = state.account
        transaction.category     = state.category
        transaction.subcategory  = state.subcategory
        transaction.costCenterId = state.costCenter?.id

        modelContext.insert(transaction)
        _ = try? ReceiptAttachmentStore.persistDrafts(state.receiptDrafts, to: transaction, in: modelContext)
        state.receiptDrafts = []

        switch state.recurrenceType {
        case .installment:
            Transaction.generateInstallments(from: transaction,
                                             total: state.installmentTotal,
                                             in: modelContext)
        case .monthly:
            Transaction.generateMonthlyRecurrences(from: transaction,
                                                   in: modelContext)
        case .annual:
            Transaction.generateAnnualRecurrences(from: transaction,
                                                  in: modelContext)
        case .none:
            break
        }

        didSave = true
        dismiss()
    }
}

// MARK: - Progress Indicator

struct ProgressIndicator: View {
    let currentStep: Int

    private let steps: [ProgressStep] = [
        .init(number: 1, icon: "dollarsign.circle", titleKey: "newTx.step1"),
        .init(number: 2, icon: "storefront", titleKey: "newTx.step2"),
        .init(number: 3, icon: "square.grid.2x2", titleKey: "newTx.step3"),
        .init(number: 4, icon: "checklist", titleKey: "newTx.step4")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.element.number) { index, step in
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(backgroundColor(for: step.number))
                            .frame(width: 36, height: 36)

                        Image(systemName: step.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(foregroundColor(for: step.number))
                    }

                    Text(t(step.titleKey))
                        .font(.caption2.weight(step.number == currentStep ? .semibold : .regular))
                        .foregroundStyle(labelColor(for: step.number))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)

                if index < steps.count - 1 {
                    Rectangle()
                        .fill(connectorColor(for: step.number))
                        .frame(maxWidth: .infinity, maxHeight: 2)
                        .offset(y: -12)
                }
            }
        }
        .animation(.easeInOut, value: currentStep)
    }

    private func backgroundColor(for step: Int) -> Color {
        if step < currentStep {
            return Color.accentColor
        }
        if step == currentStep {
            return Color.accentColor.opacity(0.14)
        }
        return Color(.systemGray6)
    }

    private func foregroundColor(for step: Int) -> Color {
        step < currentStep ? .white : (step == currentStep ? Color.accentColor : Color(.tertiaryLabel))
    }

    private func labelColor(for step: Int) -> Color {
        step <= currentStep ? .primary : .secondary
    }

    private func connectorColor(for step: Int) -> Color {
        step < currentStep ? Color.accentColor : Color(.systemGray5)
    }
}

private struct ProgressStep {
    let number: Int
    let icon: String
    let titleKey: String
}

private enum NavigationDirection {
    case forward
    case backward
}
