import SwiftUI

struct Step1AmountView: View {
    @Bindable var state: NewTransactionState

    var body: some View {
        VStack(spacing: 32) {
            // Valor em destaque
            Text(state.amount.formatted(.currency(code: "BRL")))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(typeColor)
                .padding(.top, 32)
                .animation(.easeInOut, value: state.amount)

            // Seletor de tipo
            Picker("Tipo", selection: $state.type) {
                ForEach(TransactionType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Teclado numérico customizado
            NumericKeypad(value: $state.amount)
                .padding(.horizontal)

            Spacer()
        }
    }

    private var typeColor: Color {
        switch state.type {
        case .income:   return .green
        case .expense:  return .red
        case .transfer: return .blue
        }
    }
}

// MARK: - Numeric Keypad

struct NumericKeypad: View {
    @Binding var value: Double

    private let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [",", "0", "⌫"]
    ]

    @State private var inputString = ""

    var body: some View {
        VStack(spacing: 12) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        KeyButton(label: key) { handleKey(key) }
                    }
                }
            }
        }
    }

    private func handleKey(_ key: String) {
        switch key {
        case "⌫":
            if !inputString.isEmpty { inputString.removeLast() }
        case ",":
            if !inputString.contains(",") { inputString += "," }
        default:
            if inputString.count < 10 { inputString += key }
        }
        let normalized = inputString.replacingOccurrences(of: ",", with: ".")
        value = Double(normalized) ?? 0
    }
}

struct KeyButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
