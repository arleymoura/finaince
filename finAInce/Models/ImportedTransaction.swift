import Foundation

/// A transaction extracted from a bank statement file, awaiting user confirmation.
struct ImportedTransaction: Identifiable {
    let id = UUID()
    var rawDescription: String
    var amount: Double
    var date: Date

    // Review state — starts false; user picks a decision to enable the toggle
    var isSelected: Bool = false
    var resolvedCategory:    Category? = nil
    var resolvedSubcategory: Category? = nil
    var match: RecurringMatch? = nil
    var matchDecision: MatchDecision = .undecided
    var notes: String = ""

    /// Nome limpo do estabelecimento extraído pela IA a partir da descrição bruta do extrato.
    /// Ex: "PAGO MOVIL EN ADENTIS ALCOBEN..." → "Clínica Adentis"
    /// Usado como placeName ao criar uma nova transação.
    var resolvedMerchantName: String? = nil

    /// Set during processing when the same hash already exists in a saved Transaction.
    /// These rows are shown as already-reconciled and cannot be re-selected.
    var alreadyImported: Bool = false

    /// UUID of the existing Transaction that matches this row's hash (set when alreadyImported = true).
    /// Used to open the transaction detail view when the user taps a reconciled row.
    var existingTransactionId: UUID? = nil

    /// UUID of the existing Transaction chosen via "link to existing".
    /// When set (and matchDecision == .linkToExisting), importSelected() will update
    /// that transaction's amount and mark it as paid instead of creating a new one.
    var linkedTransactionId: UUID? = nil

    /// UUID of the existing Transaction identified as the best match for the recurring pattern.
    /// Set during process() and used both for display (row preview) and import (useMatch case).
    var recommendedTransactionId: UUID? = nil

    // MARK: - Helpers

    /// Nome a usar como placeName ao criar uma nova transação.
    /// Prefere o nome limpo extraído pela IA; cai de volta para a descrição bruta se não houver.
    var effectivePlaceName: String? {
        let clean = resolvedMerchantName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !clean.isEmpty { return clean }
        let raw = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    // MARK: - Hash

    /// Stable, content-based fingerprint for duplicate detection.
    /// Format: "yyyy-MM-dd|trimmedDescription|absoluteAmount2dp"
    static func makeHash(date: Date, description: String, amount: Double) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        
        let dateStr = df.string(from: date)
        let descStr = description.normalizedForMatching() // 🔥 UNIFICADO
        let amtStr  = String(format: "%.2f", abs(amount))
        
        return "\(dateStr)|\(descStr)|\(amtStr)"
    }
}

enum MatchDecision {
    case undecided       // user hasn't decided yet
    case useMatch        // accept the suggested recurring category
    case createNew       // ignore match, use resolvedCategoryName
    case linkToExisting  // link to an existing transaction (mark it paid, no new record)
}

/// A detected recurring payment pattern that matches an imported transaction.
struct RecurringMatch {
    let categorySystemKey: String?
    let categoryName: String
    let categoryIcon: String   // SF Symbol name
    let categoryColor: String  // hex or named color string stored in Category.color
    let typicalAmount: Double
    let typicalDay: Int        // 1–31
    let occurrences: Int       // how many months this pattern appeared
    let confidence: Double     // 0.0 – 1.0

    var confidencePercent: Int { Int(confidence * 100) }

    var label: String {
        switch confidence {
        case 0.85...: return "Quase certamente"
        case 0.65...: return "Provavelmente"
        default:      return "Talvez seja"
        }
    }
}
