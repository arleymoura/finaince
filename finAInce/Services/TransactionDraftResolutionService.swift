import Foundation

struct TransactionDraftResolutionService {
    static func normalizeDraft(
        _ draft: TransactionDraft,
        categories: [Category],
        accounts: [Account]
    ) -> TransactionDraft {
        let category = resolvedCategory(for: draft, in: categories)
        let account = resolvedAccount(for: draft, in: accounts)

        return TransactionDraft(
            amount: draft.amount,
            typeRaw: draft.typeRaw,
            categorySystemKey: category?.systemKey ?? draft.categorySystemKey,
            categoryName: category?.displayName ?? category?.name ?? draft.categoryName,
            placeName: draft.placeName,
            notes: draft.notes,
            date: draft.date,
            accountName: account?.name ?? draft.accountName,
            receiptImageData: draft.receiptImageData
        )
    }

    static func resolvedCategory(for draft: TransactionDraft, in categories: [Category]) -> Category? {
        categories.first { $0.systemKey == draft.categorySystemKey }
            ?? categories.first { $0.rootSystemKey == draft.categorySystemKey }
            ?? categories.first { $0.name.localizedCaseInsensitiveCompare(draft.categoryName) == .orderedSame }
            ?? categories.first { $0.displayName.localizedCaseInsensitiveCompare(draft.categoryName) == .orderedSame }
            ?? categories.first { $0.name.localizedCaseInsensitiveContains(draft.categoryName) }
            ?? categories.first { $0.displayName.localizedCaseInsensitiveContains(draft.categoryName) }
    }

    static func resolvedAccount(for draft: TransactionDraft, in accounts: [Account]) -> Account? {
        if draft.accountName.isEmpty {
            return accounts.first(where: \.isDefault) ?? accounts.first
        }

        return accounts.first { $0.name.localizedCaseInsensitiveCompare(draft.accountName) == .orderedSame }
            ?? accounts.first { $0.name.localizedCaseInsensitiveContains(draft.accountName) }
            ?? accounts.first(where: \.isDefault)
            ?? accounts.first
    }
}
