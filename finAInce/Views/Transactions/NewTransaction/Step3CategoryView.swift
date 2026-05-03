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
                            ForEach((selected.subcategories ?? []).sorted { $0.sortOrder < $1.sortOrder }) { sub in
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
        let normalizedMerchant = TransactionCategorizationService.normalizedText(merchant)
        guard !normalizedMerchant.isEmpty else { return nil }

        let matchingTransactions = allTransactions.filter { tx in
            guard let placeName = tx.placeName, !placeName.isEmpty else { return false }
            let normalizedPlace = TransactionCategorizationService.normalizedText(placeName)
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

        guard
            let suggestion = try? await TransactionCategorizationService.suggestCategory(
                for: merchant,
                settings: settings,
                categories: rootCategories
            )
        else {
            applyDefaultCategoryIfNeeded()
            return
        }

        applyRecommendation((suggestion.category, suggestion.subcategory))
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
        category.systemKey == "other"
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

}
