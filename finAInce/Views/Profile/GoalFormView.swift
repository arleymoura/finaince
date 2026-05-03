import SwiftUI
import SwiftData

struct GoalFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var goal: Goal? // nil = nova meta

    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    @State private var title       = ""
    @State private var targetText  = ""
    @State private var selectedSymbol = "target"
    @State private var isGeneral   = true
    @State private var selectedCategory: Category? = nil
    @State private var selectedSubcategory: Category? = nil
    @State private var showSymbolPicker = false
    @State private var showCategoryPicker = false
    @State private var didChooseCustomSymbol = false

    private var isEditing: Bool { goal != nil }

    private var canSave: Bool {
        !title.isEmpty && (Double(targetText.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0
    }

    private var selectedGoalCategory: Category? {
        selectedSubcategory ?? selectedCategory
    }

    private var selectedGoalCategoryLabel: String {
        if let subcategory = selectedSubcategory, let category = selectedCategory {
            return "\(category.displayName) / \(subcategory.displayName)"
        }
        if let category = selectedCategory {
            return category.displayName
        }
        return t("goal.selectCategory")
    }

    let symbolOptions = [
        "target", "banknote.fill", "chart.pie.fill", "house.fill",
        "cart.fill", "fork.knife", "car.fill", "heart.fill",
        "cross.case.fill", "book.fill", "airplane", "gamecontroller.fill",
        "tshirt.fill", "pawprint.fill", "dumbbell.fill", "gift.fill",
        "creditcard.fill", "building.columns.fill"
    ]

    var body: some View {
        NavigationStack {
            Form {
                // Ícone + título
                Section {
                    HStack(spacing: 14) {
                        Button {
                            showSymbolPicker.toggle()
                        } label: {
                            Image(systemName: selectedSymbol)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 56, height: 56)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        TextField(t("goal.namePlaceholder"), text: $title)
                            .font(.headline)
                    }
                    .padding(.vertical, 4)

                    if showSymbolPicker {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                            ForEach(symbolOptions, id: \.self) { symbol in
                                Button {
                                    selectedSymbol = symbol
                                    didChooseCustomSymbol = true
                                    showSymbolPicker = false
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.headline)
                                        .foregroundStyle(selectedSymbol == symbol ? Color.accentColor : Color.primary)
                                        .frame(width: 44, height: 44)
                                        .background(selectedSymbol == symbol ? Color.accentColor.opacity(0.15) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Valor limite
                Section(t("goal.amount")) {
                    HStack {
                        Text((CurrencyOption(rawValue: currencyCode)
                              ?? CurrencyOption(rawValue: CurrencyOption.defaultCode)
                              ?? .usd).symbol)
                            .foregroundStyle(.secondary)
                        TextField("0,00", text: $targetText)
                            .keyboardType(.decimalPad)
                    }
                }

                // Escopo
                Section(t("goal.scope")) {
                    Toggle(t("goal.general"), isOn: $isGeneral)
                        .onChange(of: isGeneral) { _, v in
                            if v {
                                selectedCategory = nil
                                selectedSubcategory = nil
                                applyDefaultSymbol("target")
                            }
                        }

                    if !isGeneral {
                        Button {
                            showCategoryPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedGoalCategory?.icon ?? "square.grid.2x2")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(selectedGoalCategory == nil ? FinAInceColor.secondaryText : Color.accentColor)
                                    .frame(width: 32, height: 32)
                                    .background(FinAInceColor.inputFieldSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t("goal.category"))
                                        .font(.caption)
                                        .foregroundStyle(FinAInceColor.secondaryText)

                                    Text(selectedGoalCategoryLabel)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(selectedGoalCategory == nil ? FinAInceColor.secondaryText : FinAInceColor.primaryText)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(FinAInceColor.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerSheet(
                    selectedCategory: $selectedCategory,
                    selectedSubcategory: $selectedSubcategory,
                    transactionType: .expense
                )
            }
            .onChange(of: selectedGoalCategory?.id) { _, _ in
                applyDefaultSymbol(selectedGoalCategory?.icon ?? "target")
            }
            .navigationTitle(isEditing ? t("goal.edit") : t("goal.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.save")) { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear { populate() }
    }

    private func populate() {
        guard let goal else { return }
        title    = goal.title
        selectedSymbol = goal.iconName
        targetText = String(format: "%.2f", goal.targetAmount).replacingOccurrences(of: ".", with: ",")
        isGeneral  = goal.category == nil
        if let goalCategory = goal.category, let parent = goalCategory.parent {
            selectedCategory = parent
            selectedSubcategory = goalCategory
        } else {
            selectedCategory = goal.category
            selectedSubcategory = nil
        }
    }

    private func applyDefaultSymbol(_ symbol: String) {
        guard !isEditing, !didChooseCustomSymbol else { return }
        selectedSymbol = symbol
    }

    private func symbolForSave(category: Category?) -> String {
        guard !isEditing, !didChooseCustomSymbol else { return selectedSymbol }
        return category?.icon ?? selectedSymbol
    }

    private func save() {
        let amount = Double(targetText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let cat = isGeneral ? nil : selectedGoalCategory
        let symbol = symbolForSave(category: cat)

        if let goal {
            goal.title         = title
            goal.emoji         = symbol
            goal.targetAmount  = amount
            goal.category      = cat
        } else {
            let newGoal = Goal(title: title, targetAmount: amount, emoji: symbol, category: cat)
            modelContext.insert(newGoal)
        }
        dismiss()
    }
}
