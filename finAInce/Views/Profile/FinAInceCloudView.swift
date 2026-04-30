import SwiftUI
import StoreKit

// MARK: - FinAInceCloudView
//
// Tela de apresentação e compra da feature "finAInce Cloud"
// (Backup automático + sync multi dispositivos).
// Produto: Non-Consumable — "finaince.cloud.lifetime"

struct FinAInceCloudView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var entitlements = EntitlementManager.shared

    /// DEBUG only — força exibição do fluxo de compra independente do estado de entitlement
    var debugForceShowPaywall: Bool = false

    // Gradiente da marca finAInce Cloud
    private let cloudColors: [Color] = [
        Color(red: 0.20, green: 0.45, blue: 0.90),
        Color(red: 0.42, green: 0.25, blue: 0.85)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if entitlements.purchaseState == .purchasedPendingRestart && !debugForceShowPaywall {
                    purchaseSuccessSection
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            heroSection
                            contentSection
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .ignoresSafeArea(edges: .top)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if entitlements.purchaseState != .purchasedPendingRestart {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
            }
            // Erro de compra / restauração
            .alert(t("common.error"), isPresented: Binding(
                get: { entitlements.purchaseError != nil },
                set: { if !$0 { entitlements.clearError() } }
            )) {
                Button(t("common.ok"), role: .cancel) {
                    entitlements.clearError()
                }
            } message: {
                if let msg = entitlements.purchaseError {
                    Text(msg)
                }
            }
        }
        .task { await entitlements.loadProduct() }
    }

    // MARK: - Purchase Success

    private var purchaseSuccessSection: some View {
        VStack(spacing: 0) {
            Spacer()

            FinAInceCloudRestartPrompt(
                cloudColors: cloudColors,
                allowsDismissLater: true
            ) {
                dismiss()
            }
            .padding(32)
            .frame(maxWidth: contentMaxWidth)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .center) {
            LinearGradient(colors: cloudColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea(edges: .top)

            // Decorative circles
            Circle().fill(.white.opacity(0.07)).frame(width: 220, height: 220).offset(x: -100, y: -50)
            Circle().fill(.white.opacity(0.05)).frame(width: 160, height: 160).offset(x: 110, y: 40)

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 96, height: 96)
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating)
                }

                VStack(spacing: 10) {
                    Text(t("cloud.heroTitle"))
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text(t("cloud.heroSubtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                }
            }
            .frame(maxWidth: contentMaxWidth)
            .padding(.top, 72)
            .padding(.bottom, 48)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(spacing: 20) {
            featureList

            if entitlements.purchaseState == .active && !debugForceShowPaywall {
                activeConfirmationSection
            } else {
                priceSection
                ctaSection

                Text(t("cloud.legal"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: contentMaxWidth)
        .padding(20)
    }

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 920 : .infinity
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(spacing: 10) {
            CloudFeatureRow(icon: "arrow.clockwise.icloud.fill",
                            color: cloudColors[0],
                            title: t("cloud.feature1Title"),
                            subtitle: t("cloud.feature1Subtitle"))
            CloudFeatureRow(icon: "ipad.and.iphone",
                            color: cloudColors[1],
                            title: t("cloud.feature2Title"),
                            subtitle: t("cloud.feature2Subtitle"))
            CloudFeatureRow(icon: "lock.icloud.fill",
                            color: .purple,
                            title: t("cloud.feature3Title"),
                            subtitle: t("cloud.feature3Subtitle"))
            CloudFeatureRow(icon: "infinity",
                            color: .green,
                            title: t("cloud.feature4Title"),
                            subtitle: t("cloud.feature4Subtitle"))
        }
    }

    // MARK: - Price

    private var priceSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(t("cloud.priceOnce"))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .clipShape(Capsule())
                Text(t("cloud.noSubscription"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Preço vem do StoreKit (formatado na moeda local do usuário)
            Group {
                if let displayPrice = entitlements.product?.displayPrice {
                    Text(displayPrice)
                } else if entitlements.isLoadingProduct {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    Text(t("cloud.productUnavailableShort"))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 42, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)

            Text(t("cloud.priceLabel"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let productLoadError = entitlements.productLoadError {
                Text(productLoadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                Button(t("cloud.retryLoad")) {
                    Task { await entitlements.loadProduct() }
                }
                .font(.caption.weight(.semibold))
            } else if entitlements.isLoadingProduct {
                Text(t("cloud.loadingPrice"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Active Confirmation (already purchased)

    private var activeConfirmationSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: cloudColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(t("cloud.activeTitle"))
                        .font(.subheadline.bold())
                    Text(t("cloud.activeSubtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(cloudColors[0])
                    .font(.title3)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button { dismiss() } label: {
                Text(t("common.close"))
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(LinearGradient(colors: cloudColors, startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: cloudColors[0].opacity(0.35), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await entitlements.purchase() }
            } label: {
                Group {
                    if entitlements.isPurchasing {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Text(t("cloud.ctaButton")).font(.body.bold())
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(LinearGradient(colors: cloudColors, startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: cloudColors[0].opacity(0.35), radius: 8, x: 0, y: 4)
            }
            .disabled(entitlements.isPurchasing || entitlements.isRestoring || entitlements.product == nil)

            Button {
                Task { await entitlements.restorePurchases() }
            } label: {
                Group {
                    if entitlements.isRestoring {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Text(t("cloud.restorePurchase"))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .disabled(entitlements.isPurchasing || entitlements.isRestoring)
        }
    }
}

struct FinAInceCloudRestartPrompt: View {
    let cloudColors: [Color]
    let allowsDismissLater: Bool
    let onDismissLater: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: cloudColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: cloudColors[0].opacity(0.4), radius: 16, x: 0, y: 8)

            VStack(spacing: 12) {
                Text(t("cloud.successTitle"))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(t("cloud.successBody"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }

            Button {
                exit(0)
            } label: {
                Label(t("cloud.restartNow"), systemImage: "arrow.clockwise")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(LinearGradient(colors: cloudColors, startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: cloudColors[0].opacity(0.35), radius: 8, x: 0, y: 4)
            }

            if allowsDismissLater {
                Button {
                    onDismissLater()
                } label: {
                    Text(t("cloud.restartLater"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Feature Row

private struct CloudFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Banner (usado na ProfileView)

struct FinAInceCloudBanner: View {
    let state: EntitlementManager.PurchaseState

    private let cloudColors: [Color] = [
        Color(red: 0.20, green: 0.45, blue: 0.90),
        Color(red: 0.42, green: 0.25, blue: 0.85)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(state == .active ? 0.22 : 0.16))
                        .frame(width: 54, height: 54)

                    Circle()
                        .strokeBorder(.white.opacity(0.24), lineWidth: 1)
                        .frame(width: 54, height: 54)

                    Image(systemName: iconName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(t("cloud.bannerTitle"))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        Text(badgeText)
                            .font(.caption2.bold())
                            .foregroundStyle(badgeForegroundColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(badgeBackground)
                            .overlay(
                                Capsule()
                                    .strokeBorder(badgeBorderColor, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }

                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: state == .active ? "sparkles" : "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.78))
            }

            HStack(spacing: 10) {
                cloudFeaturePill(
                    icon: state == .active ? "checkmark.seal.fill" : "arrow.triangle.2.circlepath.icloud.fill",
                    text: state == .active ? t("cloud.bannerFeatureSyncActive") : t("cloud.bannerFeatureBackupSync")
                )
                cloudFeaturePill(
                    icon: "iphone.and.arrow.right.outward",
                    text: t("cloud.bannerFeatureMultidevice")
                )
                if state == .active {
                    cloudFeaturePill(
                        icon: "lock.fill",
                        text: t("cloud.bannerFeaturePrivateICloud")
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: backgroundColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.18), .clear],
                            center: .topLeading,
                            startRadius: 12,
                            endRadius: 180
                        )
                    )

                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 84, height: 84)
                            .blur(radius: 2)
                            .offset(x: 22, y: -28)
                    }
                    Spacer()
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var iconName: String {
        switch state {
        case .notPurchased:         return "icloud.fill"
        case .purchasedPendingRestart: return "arrow.clockwise.icloud.fill"
        case .active:               return "checkmark.icloud.fill"
        }
    }

    private var badgeText: String {
        switch state {
        case .notPurchased:            return t("cloud.badge")
        case .purchasedPendingRestart: return t("cloud.badgePending")
        case .active:                  return t("cloud.badgeActive")
        }
    }

    private var subtitleText: String {
        switch state {
        case .notPurchased:            return t("cloud.bannerSubtitle")
        case .purchasedPendingRestart: return t("cloud.bannerPendingSubtitle")
        case .active:                  return t("cloud.bannerActiveSubtitle")
        }
    }

    private var backgroundColors: [Color] {
        switch state {
        case .notPurchased:
            return cloudColors
        case .purchasedPendingRestart:
            return [
                Color(red: 0.23, green: 0.55, blue: 0.94),
                Color(red: 0.25, green: 0.33, blue: 0.88)
            ]
        case .active:
            return [
                Color(red: 0.11, green: 0.23, blue: 0.52),
                Color(red: 0.16, green: 0.56, blue: 0.86),
                Color(red: 0.09, green: 0.72, blue: 0.67)
            ]
        }
    }

    private var badgeBackground: Color {
        switch state {
        case .active:
            return .white
        case .purchasedPendingRestart:
            return .white.opacity(0.22)
        case .notPurchased:
            return .white.opacity(0.18)
        }
    }

    private var badgeForegroundColor: Color {
        switch state {
        case .active:
            return Color(red: 0.07, green: 0.32, blue: 0.67)
        case .purchasedPendingRestart, .notPurchased:
            return .white
        }
    }

    private var badgeBorderColor: Color {
        switch state {
        case .active:
            return .white.opacity(0.9)
        case .purchasedPendingRestart, .notPurchased:
            return .white.opacity(0.18)
        }
    }

    @ViewBuilder
    private func cloudFeaturePill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.bold())
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.14))
        .clipShape(Capsule())
    }
}
