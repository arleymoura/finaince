import SwiftUI
import UIKit

enum FinAInceLayout {
    static let regularContentMaxWidth: CGFloat = 1100
    static let modalContentMaxWidth: CGFloat = 920
}

enum FinAInceSpacing {
    static let xSmall: CGFloat = 6
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let large: CGFloat = 18
    static let xLarge: CGFloat = 24
    static let screenHorizontal: CGFloat = 24
    static let headerTop: CGFloat = 18
    static let headerBottom: CGFloat = 18
    static let itemGap: CGFloat = 12
    static let sectionGap: CGFloat = 16
}

enum FinAInceCornerRadius {
    static let largeSurface: CGFloat = 22
    static let surface: CGFloat = 18
    static let card: CGFloat = 16
    static let chip: CGFloat = 12
    static let pill: CGFloat = 999
}

enum FinAInceTypography {
    static let pageTitle = Font.system(size: 30, weight: .bold, design: .rounded)
    static let sectionTitle = Font.title2.bold()
    static let bodyStrong = Font.subheadline.weight(.semibold)
    static let cardTitle = Font.headline.weight(.semibold)
    static let action = Font.subheadline.weight(.semibold)
    static let caption = Font.caption.weight(.medium)
}

enum FinAInceColor {
    static let groupedBackground = Color(.systemGroupedBackground)
    static let primarySurface = Color(.systemBackground)
    static let secondarySurface = Color(.secondarySystemBackground)
    static let tertiarySurface = Color(.tertiarySystemBackground)
    static let elevatedSurface = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1)
                : UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        }
    )
    static let insetSurface = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
                : UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1)
        }
    )
    static let tintSurface = Color.accentColor.opacity(0.12)
    static let separator = Color(.separator)
    static let borderSubtle = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.08)
                : UIColor.black.withAlphaComponent(0.06)
        }
    )
    static let borderStrong = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.16)
                : UIColor.black.withAlphaComponent(0.12)
        }
    )
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.72)
    static let inverseText = Color.white
    static let accentText = Color.accentColor
    static let primaryActionBackground = Color.accentColor
    static let primaryActionForeground = Color.white
    static let secondaryActionBackground = secondarySurface
    static let secondaryActionForeground = primaryText
    static let ghostActionForeground = accentText
    static let inputFieldSurface = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1)
                : UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        }
    )
    static let inputFieldBorder = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.20)
                : UIColor.black.withAlphaComponent(0.14)
        }
    )

    static let regularWorkspaceTop = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.13, blue: 0.17, alpha: 1)
                : UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1)
        }
    )

    static let regularWorkspaceBottom = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)
                : UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1)
        }
    )
}

extension View {
    func finRegularContentFrame(maxWidth: CGFloat = FinAInceLayout.regularContentMaxWidth) -> some View {
        self
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    func finPageTitleStyle() -> some View {
        self
            .font(FinAInceTypography.pageTitle)
            .foregroundStyle(FinAInceColor.primaryText)
    }

    func finSecondarySurface(cornerRadius: CGFloat = FinAInceCornerRadius.card) -> some View {
        self
            .background(FinAInceColor.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func finPrimarySurface(cornerRadius: CGFloat = FinAInceCornerRadius.card) -> some View {
        self
            .background(FinAInceColor.primarySurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func finElevatedSurface(cornerRadius: CGFloat = FinAInceCornerRadius.card) -> some View {
        self
            .background(FinAInceColor.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func finInsetSurface(cornerRadius: CGFloat = FinAInceCornerRadius.card) -> some View {
        self
            .background(FinAInceColor.insetSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func finSurfaceBorder(
        _ color: Color = FinAInceColor.borderSubtle,
        cornerRadius: CGFloat = FinAInceCornerRadius.card,
        lineWidth: CGFloat = 1
    ) -> some View {
        self.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(color, lineWidth: lineWidth)
        }
    }

    func finInputFieldSurface(
        cornerRadius: CGFloat = FinAInceCornerRadius.card,
        lineWidth: CGFloat = 1.25
    ) -> some View {
        self
            .background(FinAInceColor.inputFieldSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(FinAInceColor.inputFieldBorder, lineWidth: lineWidth)
            }
    }
}

struct FinPrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FinAInceTypography.action)
            .foregroundStyle(FinAInceColor.primaryActionForeground)
            .padding(.horizontal, FinAInceSpacing.large)
            .padding(.vertical, FinAInceSpacing.medium)
            .frame(minHeight: 50)
            .background(isDestructive ? Color.red : FinAInceColor.primaryActionBackground)
            .clipShape(RoundedRectangle(cornerRadius: FinAInceCornerRadius.surface, style: .continuous))
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct FinSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FinAInceTypography.action)
            .foregroundStyle(FinAInceColor.secondaryActionForeground)
            .padding(.horizontal, FinAInceSpacing.large)
            .padding(.vertical, FinAInceSpacing.medium)
            .frame(minHeight: 50)
            .background(FinAInceColor.secondaryActionBackground)
            .clipShape(RoundedRectangle(cornerRadius: FinAInceCornerRadius.surface, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FinAInceCornerRadius.surface, style: .continuous)
                    .stroke(FinAInceColor.borderSubtle, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct FinGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FinAInceTypography.action)
            .foregroundStyle(FinAInceColor.ghostActionForeground)
            .padding(.horizontal, FinAInceSpacing.medium)
            .padding(.vertical, FinAInceSpacing.small)
            .background(FinAInceColor.tintSurface)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}
