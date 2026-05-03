import SwiftUI
import SwiftData

struct CategoryPickerSheet: View {
    @Binding var selectedCategory: Category?
    @Binding var selectedSubcategory: Category?
    let transactionType: TransactionType

    @Environment(\.dismiss) private var dismiss
    @Query private var allCategories: [Category]
    @State private var expandedCategory: Category?
    @State private var showNewCatForm = false
    @State private var showNewSubForm = false

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

    private var rootCategories: [Category] {
        allCategories
            .filter { $0.parent == nil }
            .filter {
                switch transactionType {
                case .expense:
                    return $0.type == .expense || $0.type == .both
                case .transfer:
                    return false
                }
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(rootCategories) { cat in
                            CategoryGridItem(
                                category: cat,
                                isSelected: selectedCategory?.id == cat.id
                            )
                            .onTapGesture {
                                withAnimation {
                                    selectedCategory = cat
                                    selectedSubcategory = nil
                                    expandedCategory = cat
                                }
                            }
                        }

                        AddCategoryCell(label: t("newTx.newCategoryCell"))
                            .onTapGesture { showNewCatForm = true }
                    }
                    .padding(.horizontal)

                    if let expanded = expandedCategory {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t("transaction.subcategory"))
                                .font(.headline)
                                .padding(.horizontal)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach((expanded.subcategories ?? []).sorted { $0.sortOrder < $1.sortOrder }) { sub in
                                    CategoryGridItem(
                                        category: sub,
                                        isSelected: selectedSubcategory?.id == sub.id,
                                        isSmall: true
                                    )
                                    .onTapGesture {
                                        withAnimation {
                                            selectedSubcategory = sub
                                        }
                                    }
                                }

                                AddCategoryCell(isSmall: true, label: t("newTx.newCategoryCell"))
                                    .onTapGesture { showNewSubForm = true }
                            }
                            .padding(.horizontal)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut, value: expandedCategory?.id)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(t("newTx.categoryTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.ok")) { dismiss() }
                        .fontWeight(.semibold)
                        .disabled(selectedCategory == nil)
                }
            }
        }
        .onAppear {
            if let cat = selectedCategory {
                expandedCategory = cat
            }
        }
        .sheet(isPresented: $showNewCatForm) {
            CategoryFormView { newCat in
                withAnimation {
                    selectedCategory = newCat
                    selectedSubcategory = nil
                    expandedCategory = newCat
                }
            }
        }
        .sheet(isPresented: $showNewSubForm) {
            if let parent = expandedCategory {
                CategoryFormView(parent: parent) { newSub in
                    withAnimation {
                        selectedSubcategory = newSub
                    }
                }
            }
        }
    }
}

struct AddCategoryCell: View {
    var isSmall: Bool = false
    var label: String = "Nova"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(isSmall ? .title3 : .title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: isSmall ? 40 : 52, height: isSmall ? 40 : 52)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                )

            Text(label)
                .font(isSmall ? .caption2 : .caption)
                .foregroundStyle(Color.accentColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(Color.accentColor.opacity(0.4))
        )
    }
}

struct CategoryGridItem: View {
    let category: Category
    let isSelected: Bool
    var isSmall: Bool = false
    var isRecommended: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: category.icon)
                .font(isSmall ? .title3 : .title2)
                .foregroundStyle(isSelected ? .white : Color(hex: category.color))
                .frame(width: isSmall ? 40 : 52, height: isSmall ? 40 : 52)
                .background(isSelected ? Color(hex: category.color) : Color(hex: category.color).opacity(0.15))
                .clipShape(Circle())

            Text(category.displayName)
                .font(isSmall ? .caption2 : .caption)
                .foregroundStyle(isSelected ? Color(hex: category.color) : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(isSelected ? Color(hex: category.color).opacity(0.1) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if isRecommended {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: isSmall ? 8 : 9, weight: .bold))
                    Text(t("newTx.autoBadge"))
                        .font(.system(size: isSmall ? 8 : 9, weight: .semibold))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.92))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(6)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color(hex: category.color) : Color.clear, lineWidth: 2)
        )
    }
}
