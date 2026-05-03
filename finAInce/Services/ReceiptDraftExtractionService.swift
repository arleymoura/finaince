import Foundation
import UIKit
import Vision

struct ReceiptDraftExtractionService {
    static func recognizeText(in image: UIImage) async -> String {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: "")
                return
            }

            let request = VNRecognizeTextRequest { req, _ in
                let text = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = LanguageManager.shared.effective.visionRecognitionLanguages
            request.usesLanguageCorrection = true

            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }
    }

    static func extractDraft(
        from ocrText: String,
        settings: AISettings,
        categories: [Category],
        accounts: [Account],
        fallbackText: String,
        receiptImageData: Data?
    ) async -> TransactionDraft? {
        if let cardNotificationDraft = extractCardNotificationDraft(
            from: ocrText,
            categories: categories,
            accounts: accounts,
            fallbackText: fallbackText,
            receiptImageData: receiptImageData
        ) {
            return await applySharedCategorization(
                to: cardNotificationDraft,
                settings: settings,
                categories: categories,
                accounts: accounts
            )
        }

        let categoryOptions = TransactionCategorizationService.rootExpenseCategories(from: categories).map {
            AIService.ReceiptCategoryOption(
                categorySystemKey: $0.systemKey,
                categoryName: $0.name,
                categoryDisplayName: $0.displayName
            )
        }

        let receiptResult = try? await AIService.analyzeReceipt(
            ocrText: ocrText,
            settings: settings,
            categoryOptions: categoryOptions
        )

        guard let receipt = receiptResult else { return nil }

        let trimmedStoreName = receipt.storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasStructuredReceiptData = receipt.amount > 0 && !trimmedStoreName.isEmpty
        let shouldAcceptReceipt = receipt.isReceipt || (
            hasStructuredReceiptData &&
            isLikelyReceiptOCR(
                ocrText,
                amount: receipt.amount,
                storeName: trimmedStoreName
            )
        )

        guard shouldAcceptReceipt, receipt.amount > 0 else { return nil }

        let draft = TransactionDraft(
            amount: receipt.amount,
            typeRaw: TransactionType.expense.rawValue,
            categorySystemKey: receipt.suggestedCategorySystemKey,
            categoryName: receipt.suggestedCategoryName.isEmpty ? "Comércio" : receipt.suggestedCategoryName,
            placeName: receipt.storeName,
            notes: receipt.notes.isEmpty ? fallbackText : receipt.notes,
            date: receipt.date,
            accountName: preferredDraftAccountName(
                from: accounts,
                preferCreditCard: isLikelyCardNotificationOCR(ocrText)
            ),
            receiptImageData: receiptImageData
        )

        return await applySharedCategorization(
            to: draft,
            settings: settings,
            categories: categories,
            accounts: accounts
        )
    }

    private static func applySharedCategorization(
        to draft: TransactionDraft,
        settings: AISettings,
        categories: [Category],
        accounts: [Account]
    ) async -> TransactionDraft {
        var enrichedDraft = draft

        if let suggestion = try? await TransactionCategorizationService.suggestCategory(
            for: draft.placeName,
            settings: settings,
            categories: categories
        ) {
            enrichedDraft = TransactionDraft(
                amount: draft.amount,
                typeRaw: draft.typeRaw,
                categorySystemKey: suggestion.subcategory?.systemKey ?? suggestion.category.rootSystemKey ?? suggestion.category.systemKey ?? draft.categorySystemKey,
                categoryName: suggestion.subcategory?.displayName ?? suggestion.category.displayName,
                placeName: suggestion.resolvedMerchantName ?? draft.placeName,
                notes: draft.notes,
                date: draft.date,
                accountName: draft.accountName,
                receiptImageData: draft.receiptImageData
            )
        }

        return TransactionDraftResolutionService.normalizeDraft(
            enrichedDraft,
            categories: categories,
            accounts: accounts
        )
    }

    private static func extractCardNotificationDraft(
        from ocrText: String,
        categories: [Category],
        accounts: [Account],
        fallbackText: String,
        receiptImageData: Data?
    ) -> TransactionDraft? {
        guard isLikelyCardNotificationOCR(ocrText) else { return nil }

        let merchantName = extractCardNotificationMerchant(from: ocrText)
        let amount = extractCardNotificationAmount(from: ocrText)
        guard amount > 0, !merchantName.isEmpty else { return nil }

        let inferredCategory = inferredCategoryForCardNotification(ocrText, categories: categories)
        let notes = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? merchantName
            : fallbackText

        return TransactionDraft(
            amount: amount,
            typeRaw: TransactionType.expense.rawValue,
            categorySystemKey: inferredCategory?.rootSystemKey ?? inferredCategory?.systemKey,
            categoryName: inferredCategory?.displayName ?? inferredCategory?.name ?? "Comércio",
            placeName: merchantName,
            notes: notes,
            date: nil,
            accountName: preferredDraftAccountName(from: accounts, preferCreditCard: true),
            receiptImageData: receiptImageData
        )
    }

    private static func preferredDraftAccountName(from accounts: [Account], preferCreditCard: Bool) -> String {
        if preferCreditCard,
           let creditCard = accounts.first(where: { $0.type == .creditCard && $0.isDefault }) ??
                accounts.first(where: { $0.type == .creditCard }) {
            return creditCard.name
        }

        return accounts.first(where: \.isDefault)?.name ?? accounts.first?.name ?? ""
    }

    private static func isLikelyReceiptOCR(_ ocrText: String, amount: Double, storeName: String) -> Bool {
        guard amount > 0, !storeName.isEmpty else { return false }

        let normalized = ocrText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let receiptKeywords = [
            "total", "valor total", "total pago", "grand total", "amount due",
            "subtotal", "cupom fiscal", "recibo", "nota fiscal", "invoice",
            "tax", "vat", "cnpj", "cpf", "nsu", "autorizacao", "autorizacao:",
            "visa", "mastercard", "debito", "credito", "pagamento", "payment",
            "retencao", "retencion", "tarjeta", "cartao", "compra", "purchase",
            "autorizada", "autorizado", "approved", "realizado", "se ha realizado",
            "com tua tarjeta", "con tu tarjeta", "com seu cartao", "con tu tarjeta",
            "retention", "hold", "merchant", "establecimiento"
        ]
        let keywordMatches = receiptKeywords.filter { normalized.contains($0) }.count

        let hasDate = normalized.range(
            of: #"\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2})\b"#,
            options: .regularExpression
        ) != nil

        let hasCardDigits = normalized.range(of: #"\*{2,}\d{2,4}"#, options: .regularExpression) != nil
        let hasCurrency = normalized.contains("r$") || normalized.contains("$") || normalized.contains("€")
        let hasEnoughText = normalized.count >= 24

        return hasEnoughText && (
            keywordMatches >= 2 ||
            (keywordMatches >= 1 && hasDate) ||
            (keywordMatches >= 1 && hasCurrency) ||
            (keywordMatches >= 2 && hasCardDigits)
        )
    }

    private static func isLikelyCardNotificationOCR(_ ocrText: String) -> Bool {
        let normalized = ocrText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let requiredKeywords = [
            "retencao", "retencion", "tarjeta", "cartao", "card", "purchase",
            "compra", "se ha realizado", "realizado una", "autorizada", "autorizado"
        ]
        let keywordMatches = requiredKeywords.filter { normalized.contains($0) }.count
        let hasMaskedCard = normalized.range(of: #"\*{2,}\d{2,4}"#, options: .regularExpression) != nil
        let hasAmount = extractCardNotificationAmount(from: ocrText) > 0

        return keywordMatches >= 2 && hasMaskedCard && hasAmount
    }

    private static func extractCardNotificationMerchant(from text: String) -> String {
        let patterns = [
            #"(?i)\b(?:en|em)\s+([A-Z0-9][A-Z0-9\s\-_&./]{2,}?)\s+\b(?:con\s+tu\s+tarjeta|com\s+seu\s+cartao|com\s+tua\s+tarjeta|with\s+your\s+card)\b"#,
            #"(?i)\bmerchant[:\s]+([A-Z0-9][A-Z0-9\s\-_&./]{2,})"#,
            #"(?i)\bestablecimiento[:\s]+([A-Z0-9][A-Z0-9\s\-_&./]{2,})"#
        ]

        for pattern in patterns {
            if let match = firstCapturedGroup(in: text, pattern: pattern) {
                let cleaned = match
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }

        return ""
    }

    private static func extractCardNotificationAmount(from text: String) -> Double {
        let patterns = [
            #"\b(\d+[.,]\d{2})\s?(?:EUR|USD|BRL|R\$|€|\$)\b"#,
            #"(?:retencion|retencao|purchase|compra|amount|valor)[^\d]{0,20}(\d+[.,]\d{2})\b"#
        ]

        for pattern in patterns {
            if let rawValue = firstCapturedGroup(in: text, pattern: pattern) {
                let normalized = rawValue.replacingOccurrences(of: ",", with: ".")
                if let value = Double(normalized), value > 0 {
                    return value
                }
            }
        }

        return 0
    }

    private static func inferredCategoryForCardNotification(_ ocrText: String, categories: [Category]) -> Category? {
        let normalized = ocrText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let rootCategories = TransactionCategorizationService.rootExpenseCategories(from: categories)

        let matchedKey: String
        if normalized.contains("impuesto sobre vehiculos")
            || normalized.contains("vehiculo")
            || normalized.contains("veiculo")
            || normalized.contains("motocicleta")
            || normalized.contains("matricula")
            || normalized.contains("ipva") {
            matchedKey = "transport"
        } else if normalized.contains("ayuntamiento")
            || normalized.contains("prefeitura")
            || normalized.contains("municipal")
            || normalized.contains("impuesto")
            || normalized.contains("tributaria")
            || normalized.contains("iptu")
            || normalized.contains("ibi") {
            matchedKey = "housing"
        } else if normalized.contains("glovo")
            || normalized.contains("uber eats")
            || normalized.contains("deliveroo")
            || normalized.contains("ifood")
            || normalized.contains("delivery") {
            matchedKey = "restaurants"
        } else if normalized.contains("netflix")
            || normalized.contains("spotify")
            || normalized.contains("youtube premium")
            || normalized.contains("apple tv")
            || normalized.contains("icloud")
            || normalized.contains("subscription")
            || normalized.contains("suscripcion")
            || normalized.contains("assinatura") {
            matchedKey = "subscriptions"
        } else {
            matchedKey = DefaultCategories.otherCategorySystemKey
        }

        return rootCategories.first { $0.systemKey == matchedKey }
            ?? rootCategories.first { $0.systemKey == DefaultCategories.otherCategorySystemKey }
            ?? rootCategories.first
    }

    private static func firstCapturedGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[captureRange])
    }
}
