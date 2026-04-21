import SwiftUI
import SwiftData

struct Step3CategoryView: View {
    var state: NewTransactionState

    @Query private var allCategories: [Category]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query private var aiSettings: [AISettings]

    @State private var expandedCategory:  Category?
    @State private var showCategoryForm = false
    @State private var showSubForm      = false  // nova subcategoria do expandedCategory
    @State private var recommendedCategory: Category?
    @State private var recommendedSubcategory: Category?
    @State private var recommendationAppliedForPlace = ""
    @State private var isLoadingAIRecommendation = false

    // Categorias raiz filtradas pelo tipo da transação
    var rootCategories: [Category] {
        allCategories
            .filter { $0.parent == nil }
            .filter {
                switch state.type {
                case .expense:  return $0.type == .expense || $0.type == .both
                case .transfer: return false
                }
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoadingAIRecommendation {
                    recommendationLoadingView
                }

                // Grade de categorias raiz
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(rootCategories) { category in
                        CategoryGridItem(
                            category: category,
                            isSelected: state.category?.id == category.id,
                            isRecommended: state.category?.id == category.id &&
                                recommendedCategory?.id == category.id &&
                                !isOtherCategory(category)
                        )
                        .onTapGesture {
                            selectCategory(category)
                        }
                    }

                    // Célula "Nova Categoria"
                    AddCategoryCell(label: t("newTx.newCategoryCell"))
                        .onTapGesture { showCategoryForm = true }
                }
                .padding(.horizontal)

                // Subcategorias da categoria selecionada
                if let selected = expandedCategory {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("transaction.subcategory"))
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(selected.subcategories.sorted { $0.sortOrder < $1.sortOrder }) { sub in
                                CategoryGridItem(
                                    category: sub,
                                    isSelected: state.subcategory?.id == sub.id,
                                    isSmall: true,
                                    isRecommended: state.subcategory?.id == sub.id && recommendedSubcategory?.id == sub.id
                                )
                                .onTapGesture {
                                    state.subcategory = sub
                                }
                            }

                            // Célula "Nova Subcategoria"
                            AddCategoryCell(isSmall: true, label: t("newTx.newCategoryCell"))
                                .onTapGesture { showSubForm = true }
                        }
                        .padding(.horizontal)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut, value: expandedCategory?.id)
                }
            }
            .padding(.vertical)
        }
        // Sheet: nova categoria raiz
        .onAppear {
            applyCategoryRecommendationIfNeeded()
        }
        .sheet(isPresented: $showCategoryForm) {
            CategoryFormView { newCat in
                selectCategory(newCat)
            }
        }
        // Sheet: nova subcategoria do pai expandido
        .sheet(isPresented: $showSubForm) {
            if let parent = expandedCategory {
                CategoryFormView(parent: parent) { newSub in
                    state.subcategory = newSub
                }
            }
        }
    }

    private func selectCategory(_ category: Category) {
        state.category = category
        state.subcategory = nil
        withAnimation {
            expandedCategory = category
        }
    }

    private func applyCategoryRecommendationIfNeeded() {
        let merchant = state.placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard recommendationAppliedForPlace != merchant else { return }
        recommendationAppliedForPlace = merchant

        guard !merchant.isEmpty else {
            applyDefaultCategoryIfNeeded()
            return
        }

        if let recommendation = categoryRecommendation(for: merchant) {
            applyRecommendation(recommendation)
            return
        }

        Task {
            await applyAIRecommendationIfPossible(for: merchant)
        }
    }

    private func applyRecommendation(_ recommendation: (category: Category, subcategory: Category?)) {
        recommendedCategory = recommendation.category
        recommendedSubcategory = recommendation.subcategory

        if state.category == nil {
            state.category = recommendation.category
            state.subcategory = recommendation.subcategory
        }
        expandedCategory = state.category
    }

    private func categoryRecommendation(for merchant: String) -> (category: Category, subcategory: Category?)? {
        let normalizedMerchant = normalizeMerchant(merchant)
        guard !normalizedMerchant.isEmpty else { return nil }

        let matchingTransactions = allTransactions.filter { tx in
            guard let placeName = tx.placeName, !placeName.isEmpty else { return false }
            let normalizedPlace = normalizeMerchant(placeName)
            return normalizedPlace == normalizedMerchant ||
                normalizedPlace.contains(normalizedMerchant) ||
                normalizedMerchant.contains(normalizedPlace)
        }

        guard let match = matchingTransactions.first(where: { $0.category != nil }) else {
            return nil
        }

        return (match.category!, match.subcategory)
    }

    private func applyAIRecommendationIfPossible(for merchant: String) async {
        guard state.category == nil else {
            return
        }

        guard let settings = aiSettings.first, settings.isConfigured else {
            applyDefaultCategoryIfNeeded()
            return
        }

        isLoadingAIRecommendation = true
        defer { isLoadingAIRecommendation = false }

        let options = categorySuggestionOptions()
        guard
            let suggestion = try? await AIService.suggestCategory(
                merchantName: merchant,
                settings: settings,
                options: options
            ),
            let recommendation = recommendation(from: suggestion)
        else {
            applyDefaultCategoryIfNeeded()
            return
        }

        applyRecommendation(recommendation)
    }

    private func applyDefaultCategoryIfNeeded() {
        guard state.category == nil, let defaultCategory = defaultOtherCategory else { return }
        state.category = defaultCategory
        state.subcategory = nil
        expandedCategory = defaultCategory
    }

    private var defaultOtherCategory: Category? {
        rootCategories.first(where: isOtherCategory) ?? rootCategories.first
    }

    private func isOtherCategory(_ category: Category) -> Bool {
        let otherNames = ["outros", "other", "others", "otro", "otros"]
        return otherNames.contains(normalizeMerchant(category.name))
    }

    private func categorySuggestionOptions() -> [AIService.CategorySuggestionOption] {
        rootCategories.flatMap { category in
            let subcategories = category.subcategories.sorted { $0.sortOrder < $1.sortOrder }
            let categoryOption = AIService.CategorySuggestionOption(
                categoryName: category.name,
                subcategoryName: nil
            )
            let subcategoryOptions = subcategories.map {
                AIService.CategorySuggestionOption(categoryName: category.name, subcategoryName: $0.name)
            }
            return [categoryOption] + subcategoryOptions
        }
    }

    private func recommendation(
        from suggestion: AIService.CategorySuggestionResult
    ) -> (category: Category, subcategory: Category?)? {
        let normalizedCategoryName = normalizeMerchant(suggestion.categoryName)
        let normalizedSubcategoryName = suggestion.subcategoryName.map(normalizeMerchant)

        guard let category = rootCategories.first(where: {
            normalizeMerchant($0.name) == normalizedCategoryName
        }) else {
            return nil
        }

        let subcategory = normalizedSubcategoryName.flatMap { normalizedName in
            category.subcategories.first {
                normalizeMerchant($0.name) == normalizedName
            }
        }

        return (category, subcategory)
    }

    private var recommendationLoadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.75)
            Image(systemName: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
            Text(t("newTx.findingRecommendation"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func normalizeMerchant(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Add Category Cell

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

// MARK: - Category Grid Item

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

            Text(category.name)
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
