import SwiftUI

struct WorkspaceBackground: View {
    let isRegularLayout: Bool

    var body: some View {
        Group {
            if isRegularLayout {
                LinearGradient(
                    colors: [
                        FinAInceColor.regularWorkspaceTop,
                        FinAInceColor.regularWorkspaceBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                FinAInceColor.groupedBackground
            }
        }
    }
}
