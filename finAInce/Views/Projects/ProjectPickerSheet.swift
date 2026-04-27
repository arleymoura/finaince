import SwiftUI
import SwiftData

// MARK: - ProjectPickerSheet
// Reusable sheet to select (or clear) a CostCenter from within a transaction form.

struct ProjectPickerSheet: View {
    @Binding var selectedCostCenter: CostCenter?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CostCenter.createdAt, order: .reverse) private var projects: [CostCenter]

    private var activeProjects: [CostCenter] {
        projects.filter(\.isActive)
    }

    var body: some View {
        NavigationStack {
            List {
                // Clear selection
                Button {
                    selectedCostCenter = nil
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 36)
                        Text(t("projects.noProject"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if selectedCostCenter == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Active projects
                if activeProjects.isEmpty {
                    ContentUnavailableView(
                        t("projects.empty.title"),
                        systemImage: "folder",
                        description: Text(t("projects.empty.subtitle"))
                    )
                } else {
                    ForEach(activeProjects) { project in
                        Button {
                            selectedCostCenter = project
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(hex: project.color).opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: project.icon)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color(hex: project.color))
                                }

                                Text(project.name)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if selectedCostCenter?.id == project.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(t("projects.selectProject"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
