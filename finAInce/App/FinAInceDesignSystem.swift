import SwiftUI

enum FinAInceLayout {
    static let regularContentMaxWidth: CGFloat = 1100
    static let modalContentMaxWidth: CGFloat = 920
}

enum FinAInceSpacing {
    static let screenHorizontal: CGFloat = 24
    static let headerTop: CGFloat = 18
    static let headerBottom: CGFloat = 18
    static let itemGap: CGFloat = 12
    static let sectionGap: CGFloat = 16
}

enum FinAInceCornerRadius {
    static let surface: CGFloat = 18
    static let card: CGFloat = 16
    static let chip: CGFloat = 12
}

enum FinAInceTypography {
    static let pageTitle = Font.system(size: 30, weight: .bold, design: .rounded)
    static let sectionTitle = Font.title2.bold()
    static let bodyStrong = Font.subheadline.weight(.semibold)
}

enum FinAInceColor {
    static let groupedBackground = Color(.systemGroupedBackground)
    static let secondarySurface = Color(.secondarySystemBackground)
    static let primarySurface = Color(.systemBackground)
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
            .foregroundStyle(.primary)
    }

    func finSecondarySurface(cornerRadius: CGFloat = FinAInceCornerRadius.card) -> some View {
        self
            .background(FinAInceColor.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
