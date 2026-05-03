import SwiftUI
import Combine

enum DashboardSignalSource {
    case insight(Insight)
    case opportunity(SavingsOpportunity)
}

struct DashboardSignalCardItem: Identifiable {
    let id: UUID
    let icon: String
    let color: Color
    let badgeTitle: String
    let title: String
    let body: String
    let ctaTitle: String
    let source: DashboardSignalSource
}

// MARK: - InsightCard

/// Single insight card displayed in the carousel.
struct InsightCard: View {
    let item: DashboardSignalCardItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {

                // Header row
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(item.color.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: item.icon)
                            .font(.subheadline.bold())
                            .foregroundStyle(item.color)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.badgeTitle)
                            .font(.caption2.bold())
                            .foregroundStyle(item.color)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text(item.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(FinAInceColor.primaryText)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }

                // Body
                Text(item.body)
                    .font(.caption)
                    .foregroundStyle(FinAInceColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)

                // CTA chip
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2.bold())
                    Text(item.ctaTitle)
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(item.color)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(item.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(item.color.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - InsightCarousel

/// Horizontally-paging carousel with dot indicator and auto-advance.
struct InsightCarousel: View {
    let items: [DashboardSignalCardItem]
    let onTap: (DashboardSignalCardItem) -> Void

    @State private var currentIndex = 0
    @State private var isVisible = false

    // Auto-advance timer — paused when view is off-screen
    private let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

//            // Section header
//            HStack {
//                Label("Insights", systemImage: "sparkles")
//                    .font(.headline)
//
//                Spacer()
//
//                if insights.count > 1 {
//                    Text("\(currentIndex + 1) / \(insights.count)")
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
//                        .monospacedDigit()
//                }
//            }

            if !items.isEmpty {
                // Paged cards
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        InsightCard(
                            item: item
                        ) {
                            onTap(item)
                        }
                            .tag(idx)
                            .padding(.horizontal, 1)   // avoid clipping shadow
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 140)
                .onChange(of: items.count) { _, count in
                    guard count > 0 else {
                        currentIndex = 0
                        return
                    }

                    if currentIndex >= count {
                        currentIndex = count - 1
                    }
                }
                .onReceive(timer) { _ in
                    guard isVisible, items.count > 1 else { return }

                    if currentIndex >= items.count {
                        currentIndex = 0
                    } else {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            currentIndex = (currentIndex + 1) % items.count
                        }
                    }
                }
                .onAppear  { isVisible = true  }
                .onDisappear { isVisible = false }
            }

            // Page dots
            if items.count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<items.count, id: \.self) { i in
                        Capsule()
                            .fill(i == currentIndex
                                  ? Color.accentColor
                                  : Color.secondary.opacity(0.25))
                            .frame(width: i == currentIndex ? 14 : 5, height: 5)
                            .animation(.easeInOut(duration: 0.25), value: currentIndex)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Inline pill variant (used in TransactionRowView)

/// A small tappable badge used beside the price-change percentage in a row.
struct InsightPill: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.medium))
                Image(systemName: "sparkles")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("ai.analyzePriceVariation"))
    }
}
