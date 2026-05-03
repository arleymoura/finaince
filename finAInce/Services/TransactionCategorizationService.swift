import Foundation

struct TransactionCategorizationService {
    struct Match {
        let category: Category
        let subcategory: Category?
        let resolvedMerchantName: String?
        let result: AIService.CategorySuggestionResult
    }

    static func rootExpenseCategories(from categories: [Category]) -> [Category] {
        categories
            .filter { $0.parent == nil && ($0.type == .expense || $0.type == .both) }
            .filter { !normalizedSystemKey($0.systemKey).isEmpty }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    static func suggestionOptions(from categories: [Category]) -> [AIService.CategorySuggestionOption] {
        rootExpenseCategories(from: categories).flatMap { category in
            let subcategories = (category.subcategories ?? []).sorted { $0.sortOrder < $1.sortOrder }
            let categoryOption = AIService.CategorySuggestionOption(
                categorySystemKey: category.systemKey,
                categoryName: category.name,
                categoryDisplayName: category.displayName,
                subcategorySystemKey: nil,
                subcategoryName: nil,
                subcategoryDisplayName: nil
            )
            let subcategoryOptions = subcategories.compactMap { subcategory -> AIService.CategorySuggestionOption? in
                guard !normalizedSystemKey(subcategory.systemKey).isEmpty else { return nil }
                return AIService.CategorySuggestionOption(
                    categorySystemKey: category.systemKey,
                    categoryName: category.name,
                    categoryDisplayName: category.displayName,
                    subcategorySystemKey: subcategory.systemKey,
                    subcategoryName: subcategory.name,
                    subcategoryDisplayName: subcategory.displayName
                )
            }
            return [categoryOption] + subcategoryOptions
        }
    }

    static func suggestCategory(
        for merchantName: String,
        settings: AISettings,
        categories: [Category]
    ) async throws -> Match? {
        let options = suggestionOptions(from: categories)
        guard !options.isEmpty else { return nil }

        guard let result = try await AIService.suggestCategory(
            merchantName: merchantName,
            settings: settings,
            options: options
        ) else {
            return nil
        }

        return match(result, in: categories)
    }

    static func match(_ result: AIService.CategorySuggestionResult, in categories: [Category]) -> Match? {
        let rootCategories = rootExpenseCategories(from: categories)
        let normalizedCategoryName = normalizedText(result.categoryName)
        guard !normalizedCategoryName.isEmpty else { return nil }

        let matchedCategory = rootCategories.first {
            if let systemKey = result.categorySystemKey {
                return $0.systemKey == systemKey || $0.rootSystemKey == systemKey
            }
            return normalizedText($0.name) == normalizedCategoryName
                || normalizedText($0.displayName) == normalizedCategoryName
        }
        ?? rootCategories.first {
            let name = normalizedText($0.name)
            let displayName = normalizedText($0.displayName)
            return name.contains(normalizedCategoryName)
                || normalizedCategoryName.contains(name)
                || displayName.contains(normalizedCategoryName)
                || normalizedCategoryName.contains(displayName)
        }
        ?? rootCategories.first {
            !merchantTokens(from: normalizedCategoryName).intersection(merchantTokens(from: $0.name)).isEmpty
                || !merchantTokens(from: normalizedCategoryName).intersection(merchantTokens(from: $0.displayName)).isEmpty
        }

        guard let matchedCategory else { return nil }

        let normalizedSubcategoryName = normalizedText(result.subcategoryName ?? "")
        let matchedSubcategory = (matchedCategory.subcategories ?? []).first {
            if let systemKey = result.subcategorySystemKey {
                return $0.systemKey == systemKey
            }
            return normalizedText($0.name) == normalizedSubcategoryName
                || normalizedText($0.displayName) == normalizedSubcategoryName
        }
        ?? (normalizedSubcategoryName.isEmpty ? nil : (matchedCategory.subcategories ?? []).first {
            let name = normalizedText($0.name)
            let displayName = normalizedText($0.displayName)
            return name.contains(normalizedSubcategoryName)
                || normalizedSubcategoryName.contains(name)
                || displayName.contains(normalizedSubcategoryName)
                || normalizedSubcategoryName.contains(displayName)
        })

        return Match(
            category: matchedCategory,
            subcategory: matchedSubcategory,
            resolvedMerchantName: result.resolvedMerchantName,
            result: result
        )
    }

    static func normalizedText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func merchantTokens(from value: String) -> Set<String> {
        Set(normalizedText(value).split(separator: " ").map(String.init))
    }

    private static func normalizedSystemKey(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
