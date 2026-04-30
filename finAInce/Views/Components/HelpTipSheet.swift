import SwiftUI

// MARK: - Data model

/// Representa uma dica/explicação a ser exibida no HelpTipModal.
struct HelpTipItem: Identifiable {
    let id     = UUID()
    let icon:  String
    let color: Color
    let title: String
    let body:  String
}

// MARK: - Centered modal

/// Modal centrada de ajuda contextual.
/// Usar via `.helpTipOverlay(item: $helpTip)` em qualquer view.
struct HelpTipModal: View {
    let item:      HelpTipItem
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            // ── Header colorido ───────────────────────────────────────────
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: item.icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text(item.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [item.color, item.color.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: 18, bottomLeading: 0, bottomTrailing: 0, topTrailing: 18
            )))

            // ── Corpo ─────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 20) {
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(FinAInceColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(5)

                Button(action: onDismiss) {
                    Text(t("common.understood"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [item.color, item.color.opacity(0.8)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(FinAInceColor.primarySurface)
            .clipShape(UnevenRoundedRectangle(cornerRadii: .init(
                topLeading: 0, bottomLeading: 18, bottomTrailing: 18, topTrailing: 0
            )))
        }
        .frame(maxWidth: 340)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(FinAInceColor.borderSubtle, lineWidth: 1)
        )
        .shadow(color: FinAInceColor.borderStrong.opacity(0.35), radius: 32, x: 0, y: 12)
        .padding(.horizontal, 24)
    }
}

// MARK: - Overlay modifier

/// Apresenta o `HelpTipModal` centrado na tela com scrim escuro.
/// Uso: `.helpTipOverlay(item: $helpTip)`
struct HelpTipOverlayModifier: ViewModifier {
    @Binding var item: HelpTipItem?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let tip = item {
                    ZStack {
                        FinAInceColor.primaryText.opacity(0.5)
                            .ignoresSafeArea()
                            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { item = nil } }
                            .transition(.opacity)
                            .zIndex(1)

                        HelpTipModal(item: tip) {
                            withAnimation(.easeInOut(duration: 0.2)) { item = nil }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(2)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: item?.id)
    }
}

extension View {
    func helpTipOverlay(item: Binding<HelpTipItem?>) -> some View {
        modifier(HelpTipOverlayModifier(item: item))
    }
}
