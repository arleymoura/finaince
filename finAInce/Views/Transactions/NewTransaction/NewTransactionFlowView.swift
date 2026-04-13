import SwiftUI
import SwiftData

/// Estado compartilhado entre os 4 steps da nova transação.
@Observable
final class NewTransactionState {
    var amount: Double = 0
    var type: TransactionType = .expense
    var placeName: String = ""
    var placeGoogleId: String? = nil
    var category: Category? = nil
    var subcategory: Category? = nil
    var account: Account? = nil
    var date: Date = Date()
    var recurrenceType: RecurrenceType = .none
    var installmentTotal: Int = 2
    var notes: String = ""
}

struct NewTransactionFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var state = NewTransactionState()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Indicador de progresso
                ProgressIndicator(currentStep: step, totalSteps: 4)
                    .padding()

                // Conteúdo do step atual
                Group {
                    switch step {
                    case 1: Step1AmountView(state: state)
                    case 2: Step2LocationView(state: state)
                    case 3: Step3CategoryView(state: state)
                    case 4: Step4DetailsView(state: state,
                                             onSave: saveTransaction)
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
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
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            if step > 1 {
                Button("← Voltar") { step -= 1 }
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button("Próximo →") { step += 1 }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
        }
        .padding()
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return state.amount > 0
        case 2: return true   // local é opcional
        case 3: return state.category != nil
        default: return true
        }
    }

    private var stepTitle: String {
        switch step {
        case 1: return "Valor"
        case 2: return "Local"
        case 3: return "Categoria"
        case 4: return "Detalhes"
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
            installmentTotal: state.recurrenceType == .installment ? state.installmentTotal : nil
        )
        transaction.account = state.account
        transaction.category = state.category
        transaction.subcategory = state.subcategory

        modelContext.insert(transaction)

        if state.recurrenceType == .installment {
            Transaction.generateInstallments(from: transaction,
                                             total: state.installmentTotal,
                                             in: modelContext)
        }

        dismiss()
    }
}

// MARK: - Progress Indicator

struct ProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.accentColor : Color(.systemGray5))
                    .frame(height: 4)
                    .animation(.easeInOut, value: currentStep)
            }
        }
    }
}
