import SwiftUI
import SwiftData

struct Step4DetailsView: View {
    @Bindable var state: NewTransactionState
    let onSave: () -> Void

    @Query private var accounts: [Account]

    var defaultAccount: Account? {
        accounts.first { $0.isDefault } ?? accounts.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Resumo da transação
                transactionSummary

                // Formulário de detalhes
                VStack(spacing: 0) {
                    accountRow
                    Divider().padding(.leading, 56)
                    dateRow
                    Divider().padding(.leading, 56)
                    recurrenceRow
                    if state.recurrenceType == .installment {
                        Divider().padding(.leading, 56)
                        installmentRow
                    }
                    Divider().padding(.leading, 56)
                    notesRow
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Botão salvar
                Button(action: onSave) {
                    Label("Salvar Transação", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .onAppear {
            if state.account == nil {
                state.account = defaultAccount
            }
        }
    }

    // MARK: - Summary

    private var transactionSummary: some View {
        HStack(spacing: 16) {
            Image(systemName: state.category?.icon ?? state.type.icon)
                .font(.title)
                .foregroundStyle(Color(hex: state.category?.color ?? "#007AFF"))
                .frame(width: 56, height: 56)
                .background(Color(hex: state.category?.color ?? "#007AFF").opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(state.placeName.isEmpty ? (state.category?.name ?? "Transação") : state.placeName)
                    .font(.headline)
                Text(state.amount.formatted(.currency(code: "BRL")))
                    .font(.title2.bold())
                    .foregroundStyle(state.type == .income ? Color.green : Color.red)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Form Rows

    private var accountRow: some View {
        DetailRow(icon: "creditcard.fill", label: "Conta") {
            Picker("Conta", selection: $state.account) {
                Text("Nenhuma").tag(Account?.none)
                ForEach(accounts) { account in
                    Label(account.name, systemImage: account.icon).tag(Account?.some(account))
                }
            }
            .labelsHidden()
        }
    }

    private var dateRow: some View {
        DetailRow(icon: "calendar", label: "Data") {
            DatePicker("", selection: $state.date, displayedComponents: .date)
                .labelsHidden()
        }
    }

    private var recurrenceRow: some View {
        DetailRow(icon: "repeat", label: "Recorrência") {
            Picker("Recorrência", selection: $state.recurrenceType) {
                ForEach(RecurrenceType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
            .labelsHidden()
        }
    }

    private var installmentRow: some View {
        DetailRow(icon: "square.stack.fill", label: "Parcelas") {
            Stepper("\(state.installmentTotal)x",
                    value: $state.installmentTotal,
                    in: 2...48)
                .fixedSize()
        }
    }

    private var notesRow: some View {
        DetailRow(icon: "note.text", label: "Notas") {
            TextField("Opcional", text: $state.notes)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Detail Row

struct DetailRow<Content: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            Text(label)
                .font(.subheadline)
            Spacer()
            content()
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
