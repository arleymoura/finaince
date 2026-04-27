import SwiftUI

struct GoalProgressCard: View {
    let goal: Goal
    let spent: Double           // ja pago
    let forecast: Double        // pago + pendente
    var onTap: (() -> Void)? = nil
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    private var progress: Double {
        goal.targetAmount > 0 ? min(forecast / goal.targetAmount, 1.5) : 0
    }

    private var paidProgress: Double {
        goal.targetAmount > 0 ? min(spent / goal.targetAmount, 1.0) : 0
    }

    private var percentage: Int {
        guard goal.targetAmount > 0 else { return 0 }
        return Int((forecast / goal.targetAmount) * 100)
    }

    private var status: (message: String, color: Color) {
        switch percentage {
        case ..<50:    return ("Ótimo ritmo! Continue assim", .green)
        case 50..<75:  return ("Indo bem, fique atento", .green)
        case 75..<90:  return ("Atenção! Chegando no limite", .orange)
        case 90..<100: return ("Quase no limite! Cuidado", .red)
        default:       return ("Meta ultrapassada", .red)
        }
    }

    var body: some View {
        cardContent
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
    }

    private var cardContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: goal.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status.color)
                    .frame(width: 32, height: 32)
                    .background(status.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.title)
                        .font(.subheadline.weight(.semibold))
                    if let cat = goal.category {
                        HStack(spacing: 3) {
                            Text(cat.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if onTap != nil {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(percentage)%")
                        .font(.subheadline.bold())
                        .foregroundStyle(status.color)
                    Text(t("goal.ofAmount", goal.targetAmount.asCurrency(currencyCode)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemFill))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(status.color.opacity(0.35))
                        .frame(width: geo.size.width * min(forecast / max(goal.targetAmount, 0.01), 1.0), height: 12)
                        .animation(.easeOut(duration: 0.5), value: forecast)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(status.color)
                        .frame(width: geo.size.width * paidProgress, height: 12)
                        .animation(.easeOut(duration: 0.5), value: spent)

                    Rectangle()
                        .fill(Color(.systemBackground))
                        .frame(width: 2, height: 16)
                        .offset(x: geo.size.width - 2)
                }
            }
            .frame(height: 12)

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t("goal.paidAmount", spent.asCurrency(currencyCode)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if forecast > spent {
                        Text(t("goal.expectedAmount", forecast.asCurrency(currencyCode)))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Text(status.message)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(status.color)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(12)
        .background(status.color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CompactGoalProgressCard: View {
    let goal: Goal
    let spent: Double
    let forecast: Double
    var onTap: (() -> Void)? = nil
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    private var percentage: Int {
        guard goal.targetAmount > 0 else { return 0 }
        return Int((forecast / goal.targetAmount) * 100)
    }

    private var progress: Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(forecast / goal.targetAmount, 1.0)
    }

    private var statusColor: Color {
        switch percentage {
        case ..<75: return .green
        case 75..<90: return .orange
        default: return .red
        }
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: goal.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 26, height: 26)
                        .background(statusColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    Spacer(minLength: 4)

                    Text("\(percentage)%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Text(forecast.asCurrency(currencyCode))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemFill))
                        Capsule()
                            .fill(statusColor)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 5)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(statusColor.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
