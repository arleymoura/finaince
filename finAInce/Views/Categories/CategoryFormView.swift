import SwiftUI
import SwiftData

// MARK: - Category Form (criar / editar categorias e subcategorias)

struct CategoryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    var category: Category? = nil
    var parent: Category? = nil
    var onCreated: ((Category) -> Void)? = nil

    @State private var name         = ""
    @State private var icon         = "tag.fill"
    @State private var colorHex     = "#007AFF"
    @State private var categoryType: CategoryType = .expense
    @State private var showSymbolPicker = false

    private var isEditing:    Bool { category != nil }
    private var isSubcategory: Bool { parent != nil || category?.parent != nil }

    private var navTitle: String {
        if isEditing     { return t("category.edit") }
        if isSubcategory { return t("category.newSub") }
        return t("category.new")
    }

    private var effectiveColor: String {
        if let c = parent?.color           { return c }
        if let c = category?.parent?.color { return c }
        return colorHex
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // ── Preview ────────────────────────────────────────────────
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: icon)
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                                .background(Color(hex: effectiveColor))
                                .clipShape(Circle())
                            Text(name.isEmpty ? t("category.namePlaceholder") : name)
                                .font(.headline)
                                .foregroundStyle(name.isEmpty ? .secondary : .primary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                // ── Nome ───────────────────────────────────────────────────
                Section(t("category.nameLabel")) {
                    TextField(
                        isSubcategory
                            ? t("category.namePlaceholderSub")
                            : t("category.namePlaceholderExpense"),
                        text: $name
                    )
                }

                // ── Ícone ──────────────────────────────────────────────────
                Section(t("category.iconLabel")) {
                    Button { showSymbolPicker = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon)
                                .font(.title3)
                                .foregroundStyle(Color(hex: effectiveColor))
                                .frame(width: 36, height: 36)
                                .background(Color(hex: effectiveColor).opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(icon)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // ── Cor — apenas categorias raiz ───────────────────────────
                if !isSubcategory {
                    Section(t("category.colorLabel")) {
                        ColorPaletteView(selected: $colorHex)
                            .padding(.vertical, 4)
                    }
                }

                // ── Tipo — apenas categorias raiz ──────────────────────────
                if !isSubcategory {
                    Section {
                        Picker(t("category.typeLabel"), selection: $categoryType) {
                            ForEach(CategoryType.allCases, id: \.self) { tp in
                                Text(tp.label).tag(tp)
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text(t("category.typeLabel"))
                    } footer: {
                        Text(categoryType == .expense
                             ? t("category.footerExpense")
                             : t("category.footerBoth"))
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.save"), action: save)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showSymbolPicker) {
                SFSymbolPickerView(selected: $icon)
                    .presentationDetents([.large])
            }
            .onAppear(perform: loadExistingData)
        }
    }

    // MARK: - Helpers

    private func loadExistingData() {
        guard let cat = category else { return }
        name         = cat.name
        icon         = cat.icon
        colorHex     = cat.color
        categoryType = cat.type
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let existing = category {
            existing.name = trimmed
            existing.icon = icon
            if !isSubcategory {
                existing.color = colorHex
                existing.type  = categoryType
            }
        } else {
            let newColor = isSubcategory ? (parent?.color ?? colorHex) : colorHex
            let newType  = isSubcategory ? (parent?.type  ?? categoryType) : categoryType
            let newCat   = Category(
                name:     trimmed,
                icon:     icon,
                color:    newColor,
                type:     newType,
                isSystem: false,
                sortOrder: 999
            )
            newCat.parent = parent
            modelContext.insert(newCat)
            onCreated?(newCat)
        }
        dismiss()
    }
}

// MARK: - Color Palette

struct ColorPaletteView: View {
    @Binding var selected: String

    private let palette: [String] = [
        "#FF3B30", "#FF6B35", "#FF9500", "#FF9F0A", "#FFCC00",
        "#34C759", "#30D158", "#00C7BE", "#32ADE6", "#007AFF",
        "#5856D6", "#5E5CE6", "#AF52DE", "#FF2D55", "#FF375F",
        "#A2845E", "#8E8E93", "#636366"
    ]

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(palette, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 36, height: 36)
                    .overlay {
                        if selected == hex {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay {
                        Circle()
                            .stroke(
                                selected == hex ? Color.primary.opacity(0.4) : Color.clear,
                                lineWidth: 3
                            )
                    }
                    .onTapGesture { selected = hex }
            }
        }
    }
}

// MARK: - SF Symbol Picker

struct SFSymbolPickerView: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 8)]

    private var filteredSymbols: [String] {
        guard !searchText.isEmpty else { return allSFSymbolGroups.flatMap(\.symbols) }
        return sfSymbolsMatching(searchText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if searchText.isEmpty {
                    ForEach(allSFSymbolGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 12)
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(group.symbols, id: \.self) { sym in
                                    symbolCell(sym)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 24)
                } else {
                    if filteredSymbols.isEmpty {
                        ContentUnavailableView(
                            t("symbolPicker.noResults"),
                            systemImage: "magnifyingglass",
                            description: Text(t("symbolPicker.noResultsDesc"))
                        )
                        .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(filteredSymbols, id: \.self) { sym in
                                symbolCell(sym)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(t("symbolPicker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: t("symbolPicker.search"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.ok")) { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func symbolCell(_ sym: String) -> some View {
        let isSelected = selected == sym
        Button { selected = sym } label: {
            Image(systemName: sym)
                .font(.title2)
                .frame(width: 52, height: 52)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.15)
                        : Color(.secondarySystemBackground)
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}
