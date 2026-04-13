import SwiftUI
import SwiftData

struct Step3CategoryView: View {
    var state: NewTransactionState

    @Query private var allCategories: [Category]

    @State private var expandedCategory: Category?

    // Categorias raiz filtradas pelo tipo da transação
    var rootCategories: [Category] {
        allCategories
            .filter { $0.parent == nil }
            .filter {
                switch state.type {
                case .income:           return $0.type == .income  || $0.type == .both
                case .expense:          return $0.type == .expense || $0.type == .both
                case .transfer:         return false
                }
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Grade de categorias raiz
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(rootCategories) { category in
                        CategoryGridItem(
                            category: category,
                            isSelected: state.category?.id == category.id
                        )
                        .onTapGesture {
                            selectCategory(category)
                        }
                    }
                }
                .padding(.horizontal)

                // Subcategorias da categoria selecionada
                if let selected = expandedCategory, !selected.subcategories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subcategoria")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(selected.subcategories.sorted { $0.sortOrder < $1.sortOrder }) { sub in
                                CategoryGridItem(
                                    category: sub,
                                    isSelected: state.subcategory?.id == sub.id,
                                    isSmall: true
                                )
                                .onTapGesture {
                                    state.subcategory = sub
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut, value: expandedCategory?.id)
                }
            }
            .padding(.vertical)
        }
    }

    private func selectCategory(_ category: Category) {
        state.category = category
        state.subcategory = nil
        withAnimation {
            expandedCategory = category
        }
    }
}

// MARK: - Category Grid Item

struct CategoryGridItem: View {
    let category: Category
    let isSelected: Bool
    var isSmall: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: category.icon)
                .font(isSmall ? .title3 : .title2)
                .foregroundStyle(isSelected ? .white : Color(hex: category.color))
                .frame(width: isSmall ? 40 : 52, height: isSmall ? 40 : 52)
                .background(isSelected ? Color(hex: category.color) : Color(hex: category.color).opacity(0.15))
                .clipShape(Circle())

            Text(category.name)
                .font(isSmall ? .caption2 : .caption)
                .foregroundStyle(isSelected ? Color(hex: category.color) : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isSelected ? Color(hex: category.color).opacity(0.1) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color(hex: category.color) : Color.clear, lineWidth: 2)
        )
    }
}
