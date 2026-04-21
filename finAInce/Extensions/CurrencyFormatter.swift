import Foundation

enum CurrencyOption: String, CaseIterable, Identifiable {
    case brl = "BRL"
    case usd = "USD"
    case eur = "EUR"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .brl: return t("currency.brl")
        case .usd: return t("currency.usd")
        case .eur: return t("currency.eur")
        }
    }

    var symbol: String {
        switch self {
        case .brl: return "R$"
        case .usd: return "$"
        case .eur: return "€"
        }
    }

    /// Locale that positions the symbol on the LEFT for all three currencies.
    var locale: Locale {
        switch self {
        case .brl: return Locale(identifier: "pt_BR")
        case .usd: return Locale(identifier: "en_US")
        case .eur: return Locale(identifier: "en_IE") // Irish English → "€1,234.56"
        }
    }
}

extension Double {
    /// Formats the value as currency with the symbol on the left.
    /// - Parameter code: ISO 4217 code, e.g. "BRL", "USD", "EUR". Defaults to UserDefaults value.
    func asCurrency(_ code: String = UserDefaults.standard.string(forKey: "app.currencyCode") ?? "BRL") -> String {
        let option = CurrencyOption(rawValue: code) ?? .brl
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = option.rawValue
        formatter.locale = option.locale
        return formatter.string(from: NSNumber(value: self)) ?? "\(option.symbol) \(self)"
    }
}
