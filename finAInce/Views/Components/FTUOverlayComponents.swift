import SwiftUI

// MARK: - Shared FTU visual components
// Used by DashboardView and TransactionListView (and any future FTU flows).

// MARK: - Pulsing ring

/// Animated border ring that highlights a specific rect on screen.
/// Create with `.id(stepIndex)` to reset the pulse animation on step change.
struct FTUPulsingRing: View {
    let color:  Color
    let rect:   CGRect
    let radius: CGFloat

    @State private var pulsing   = false
    @State private var isVisible = false

    var body: some View {
        ZStack {
            // Expanding ghost ring — fades out as it grows
            RoundedRectangle(cornerRadius: radius)
                .stroke(color.opacity(pulsing ? 0 : 0.45), lineWidth: 3)
                .frame(width: rect.width, height: rect.height)
                .scaleEffect(pulsing ? 1.08 : 1.0)

            // Solid ring — always visible
            RoundedRectangle(cornerRadius: radius)
                .stroke(color, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
        }
        .position(x: rect.midX, y: rect.midY)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            // Wait for scroll / layout to settle before showing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVisible = true
                }
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false).delay(0.15)) {
                    pulsing = true
                }
            }
        }
    }
}

// MARK: - Bottom card

/// The bottom-pinned explanation card shown during any FTU step.
struct FTUBottomCard: View {
    let icon:         String
    let color:        Color
    let title:        String
    let message:      String
    let currentIndex: Int
    let totalSteps:   Int
    let isLastStep:   Bool
    let onNext:       () -> Void
    let onClose:      () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            // ── Icon + title + description + close ──────────────────────────
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 46, height: 46)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // ── Progress dots + skip + next ─────────────────────────────────
            HStack(alignment: .center, spacing: 0) {

                // Animated dots
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(i == currentIndex ? color : Color(.systemGray4))
                            .frame(width: i == currentIndex ? 20 : 7, height: 7)
                            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: currentIndex)
                    }
                }

                Spacer()

                if !isLastStep {
                    Button(t("ftu.skip"), action: onClose)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 12)
                }

                Button(action: onNext) {
                    HStack(spacing: 5) {
                        Text(isLastStep ? t("dashboard.ftu.done") : t("common.next"))
                        if !isLastStep {
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.14), radius: 28, x: 0, y: -6)
        )
    }
}
