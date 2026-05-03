import SwiftUI

struct Step1AmountView: View {
    @Bindable var state: NewTransactionState
    /// Quando `true`, o scanner abre automaticamente no primeiro `onAppear`.
    var openScannerOnAppear: Bool = false

    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 28) {

            // ── Display do valor ────────────────────────────────────────
            ZStack(alignment: .topTrailing) {
                Text(state.amount.asCurrency(currencyCode))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(typeColor)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .contentTransition(.numericText())   // troca fluida sem lag

                Button { showScanner = true } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .padding(10)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 16)
            }

            if state.allowsKindSelection {
                transactionKindPicker
            }

            // ── Teclado por centavos ────────────────────────────────────
            CentsKeypad(amount: $state.amount)
                .padding(.horizontal)

            Spacer()
        }
        .sheet(isPresented: $showScanner) {
            ReceiptScannerView(state: state)
        }
        // Abre o scanner automaticamente quando o fluxo começa via "Escanear recibo"
        .onAppear {
            if openScannerOnAppear {
                // Pequeno delay para o sheet do flow terminar de apresentar
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showScanner = true
                }
            }
        }
    }

    private var typeColor: Color {
        switch state.kind {
        case .regular:
            return .red
        case .cardBillPayment:
            return .blue
        case .cashWithdrawal:
            return .orange
        }
    }

    private var transactionKindPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("newTx.type"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FinAInceColor.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                transactionKindButton(.regular, icon: "minus.circle.fill", color: .red)

                if state.allowsKindSelection {
                    transactionKindButton(.cardBillPayment, icon: "creditcard.and.123", color: .blue)
                    transactionKindButton(.cashWithdrawal, icon: "banknote.fill", color: .orange)
                }
            }
        }
        .padding(.horizontal)
    }

    private func transactionKindButton(_ kind: TransactionKind, icon: String, color: Color) -> some View {
        let isSelected = state.kind == kind

        return Button {
            state.kind = kind
            switch kind {
            case .regular:
                state.type = .expense
                state.destinationAccount = nil
            case .cardBillPayment:
                state.type = .transfer
                state.category = nil
                state.subcategory = nil
                state.costCenter = nil
            case .cashWithdrawal:
                state.type = .transfer
                state.category = nil
                state.subcategory = nil
                state.costCenter = nil
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : color)
                    .frame(width: 42, height: 42)
                    .background(isSelected ? color : color.opacity(0.14))
                    .clipShape(Circle())

                Text(kind.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? FinAInceColor.primaryText : FinAInceColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .background(isSelected ? color.opacity(0.12) : FinAInceColor.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? color : FinAInceColor.borderSubtle, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cents Keypad

/// Entrada por centavos: o usuário digita apenas dígitos e a máscara
/// posiciona os decimais automaticamente — igual ao Nubank / PicPay.
/// Ex: 1 → 0,01 · 12 → 0,12 · 123 → 1,23 · 1234 → 12,34
struct CentsKeypad: View {
    @Binding var amount: Double

    // Estado local em centavos para evitar conversões Double em todo keypress
    @State private var cents: Int = 0

    private static let maxCents = 9_999_999   // R$ 99.999,99

    private let rows: [[CentsKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.double0,  .digit(0), .backspace],
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        let key = rows[r][c]
                        KeypadButton(key: key) { press(key) }
                    }
                }
            }
        }
        // Sincroniza cents quando o valor é alterado externamente (ex: scanner)
        .onAppear { cents = Int((amount * 100).rounded()) }
        .onChange(of: amount) { _, newAmount in
            let external = Int((newAmount * 100).rounded())
            if external != cents { cents = external }
        }
    }

    private func press(_ key: CentsKey) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        switch key {
        case .digit(let d):
            let next = cents * 10 + d
            guard next <= Self.maxCents else { return }
            cents = next
        case .double0:
            let next = cents * 100
            guard next <= Self.maxCents else { return }
            cents = next
        case .backspace:
            cents = cents / 10
        }

        // Atualiza o binding SEM animação extra — ContentTransition cuida do display
        amount = Double(cents) / 100.0
    }
}

// MARK: - Key model

private enum CentsKey {
    case digit(Int)
    case double0
    case backspace

    var label: String {
        switch self {
        case .digit(let d): return "\(d)"
        case .double0:      return "00"
        case .backspace:    return "⌫"
        }
    }

    var isBackspace: Bool {
        if case .backspace = self { return true }
        return false
    }
}

// MARK: - KeypadButton

private struct KeypadButton: View {
    let key: CentsKey
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button {
            action()
        } label: {
            Text(key.label)
                .font(key.isBackspace
                      ? .title2
                      : .system(size: 26, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(
                    key.isBackspace
                        ? Color(.tertiarySystemBackground)
                        : Color(.secondarySystemBackground)
                )
                .foregroundStyle(
                    key.isBackspace ? Color.secondary : Color.primary
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .scaleEffect(pressed ? 0.93 : 1.0)
        }
        .buttonStyle(.plain)
        ._onButtonGesture(pressing: { isPressing in
            withAnimation(.easeInOut(duration: 0.08)) { pressed = isPressing }
        }, perform: {})
    }
}
