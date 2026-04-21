//
//  String+Normalize.swift
//  finAInce
//
//  Created by Arley Moura on 19/04/2026.
//

import Foundation

extension String {
    func normalizedForMatching() -> String {
        self
            .lowercased()
            .replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression) // 🔥 remove tudo que não for letra
            .folding(options: [.diacriticInsensitive], locale: .current)
    }
}
