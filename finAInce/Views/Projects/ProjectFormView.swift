import SwiftUI
import SwiftData

// MARK: - ProjectFormView  (Create / Edit)

struct ProjectFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    /// Pass an existing CostCenter to edit, nil to create.
    var project: CostCenter? = nil

    // MARK: - Form state
    @State private var name:       String  = ""
    @State private var desc:       String  = ""
    @State private var icon:       String  = "folder.fill"
    @State private var color:      String  = "#007AFF"
    @State private var isActive:   Bool    = true
    @State private var hasBudget:  Bool    = false
    @State private var budgetText: String  = ""   // same pattern as TransactionEditView.amountText
    @State private var hasStart:   Bool    = false
    @State private var startDate:  Date    = Date()
    @State private var hasEnd:     Bool    = false
    @State private var endDate:    Date    = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()

    @State private var showIconPicker = false
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { project != nil }
    private var canSave:   Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // ── Identity ──────────────────────────────────────────────
                Section {
                    // Icon + Color + Name row
                    HStack(spacing: 14) {
                        Button { showIconPicker = true } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: color))
                                    .frame(width: 52, height: 52)
                                Image(systemName: icon)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)

                        TextField(t("projects.name"), text: $name)
                            .font(.body)
                            .focused($nameFocused)
                    }
                    .padding(.vertical, 4)

                    // Color picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(CostCenter.colorOptions, id: \.self) { hex in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) { color = hex }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 30, height: 30)
                                        if color == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                // ── Description ───────────────────────────────────────────
                Section(t("projects.description")) {
                    TextField(t("common.optional"), text: $desc, axis: .vertical)
                        .font(.body)
                        .lineLimit(3...6)
                }

                // ── Status ────────────────────────────────────────────────
                Section {
                    Toggle(t("projects.isActive"), isOn: $isActive)
                }

                // ── Budget ────────────────────────────────────────────────
                Section {
                    Toggle(t("projects.budget"), isOn: $hasBudget.animation())
                    if hasBudget {
                        HStack(spacing: 8) {
                            Text(t("projects.budget"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("0,00", text: $budgetText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                // ── Dates ─────────────────────────────────────────────────
                Section(t("projects.dates")) {
                    Toggle(t("projects.startDate"), isOn: $hasStart.animation())
                    if hasStart {
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                    }

                    Toggle(t("projects.endDate"), isOn: $hasEnd.animation())
                    if hasEnd {
                        DatePicker("", selection: $endDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
            }
            .navigationTitle(isEditing ? t("projects.edit") : t("projects.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.save")) { saveProject() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear { loadIfEditing() }
            .sheet(isPresented: $showIconPicker) {
                ProjectIconPickerSheet(selectedIcon: $icon, selectedColor: color)
            }
        }
    }

    // MARK: - Helpers

    private func loadIfEditing() {
        guard let p = project else {
            nameFocused = true
            return
        }
        name      = p.name
        desc      = p.desc ?? ""
        icon      = p.icon
        color     = p.color
        isActive  = p.isActive
        hasBudget  = p.budget != nil
        budgetText = p.budget.map { String(format: "%.2f", $0) } ?? ""
        hasStart  = p.startDate != nil
        startDate = p.startDate ?? Date()
        hasEnd    = p.endDate != nil
        endDate   = p.endDate ?? Date()
    }

    private func parsedBudget() -> Double? {
        guard hasBudget else { return nil }
        let normalized = budgetText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return Double(normalized).flatMap { $0 > 0 ? $0 : nil }
    }

    private func saveProject() {
        if let p = project {
            // Edit
            p.name      = name.trimmingCharacters(in: .whitespaces)
            p.desc      = desc.isEmpty ? nil : desc
            p.icon      = icon
            p.color     = color
            p.isActive  = isActive
            p.budget    = parsedBudget()
            p.startDate = hasStart ? startDate : nil
            p.endDate   = hasEnd ? endDate : nil
            p.updatedAt = Date()
        } else {
            // Create
            let newProject = CostCenter(
                name:      name.trimmingCharacters(in: .whitespaces),
                desc:      desc.isEmpty ? nil : desc,
                icon:      icon,
                color:     color,
                isActive:  isActive,
                startDate: hasStart ? startDate : nil,
                endDate:   hasEnd ? endDate : nil,
                budget:    parsedBudget()
            )
            modelContext.insert(newProject)
        }
        dismiss()
    }
}

// MARK: - Icon Picker Sheet

private struct ProjectIconPickerSheet: View {
    @Binding var selectedIcon: String
    let selectedColor: String
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(CostCenter.iconOptions, id: \.self) { symbol in
                        Button {
                            selectedIcon = symbol
                            dismiss()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedIcon == symbol
                                          ? Color(hex: selectedColor)
                                          : Color(.secondarySystemBackground))
                                    .frame(height: 56)
                                Image(systemName: symbol)
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(selectedIcon == symbol ? .white : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(t("projects.icon"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
