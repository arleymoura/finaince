import SwiftUI

struct WorkspaceBackground: View {
    let isRegularLayout: Bool

    var body: some View {
        Group {
            if isRegularLayout {
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.97, blue: 0.99),
                        Color(red: 0.94, green: 0.95, blue: 0.97)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Color(.systemGroupedBackground)
            }
        }
    }
}
