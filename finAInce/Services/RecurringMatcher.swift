import Foundation

enum RecurringMatcher {

    // MARK: - Pattern

    struct Pattern {
        var categorySystemKey: String?
        var categoryName: String
        var categoryIcon: String
        var categoryColor: String
        var typicalAmount: Double
        var typicalDay: Int
        var occurrences: Int
        var maxVariance: Double
    }

    // MARK: - detectPatterns

    static func detectPatterns(from transactions: [TransactionSnapshot]) -> [Pattern] {
        // 1. Filter only expenses
        let expenses = transactions.filter { $0.isExpense }

        // 2. Group by stable category identity
        var grouped: [String: [TransactionSnapshot]] = [:]
        var categoryNames: [String: String] = [:]
        var categoryIcons: [String: String] = [:]
        var categoryColors: [String: String] = [:]
        var categorySystemKeys: [String: String?] = [:]
        for tx in expenses {
            let groupKey = tx.rootCategorySystemKey ?? tx.categorySystemKey ?? tx.categoryName
            grouped[groupKey, default: []].append(tx)
            categoryNames[groupKey] = tx.categoryName
            categoryIcons[groupKey] = tx.categoryIcon
            categoryColors[groupKey] = tx.categoryColor
            categorySystemKeys[groupKey] = tx.rootCategorySystemKey ?? tx.categorySystemKey
        }

        var patterns: [Pattern] = []

        for (groupKey, txs) in grouped {
            // 3. Skip if fewer than 2 distinct months
            let cal = Calendar.current
            let distinctMonths = Set(txs.map { tx -> String in
                let comps = cal.dateComponents([.year, .month], from: tx.date)
                return "\(comps.year ?? 0)-\(comps.month ?? 0)"
            })
            guard distinctMonths.count >= 2 else { continue }

            // 4. Cluster by amount (15% relative tolerance)
            let clusters = clusterByAmount(txs, tolerance: 0.15)

            // 5. For clusters with >= 2 items, compute stats
            for cluster in clusters where cluster.count >= 2 {
                let avgAmount = cluster.reduce(0.0) { $0 + $1.amount } / Double(cluster.count)
                let avgDay: Int = {
                    let totalDays = cluster.reduce(0) { $0 + cal.component(.day, from: $1.date) }
                    return totalDays / cluster.count
                }()
                let maxVariance = cluster.map { abs($0.amount - avgAmount) }.max() ?? 0.0

                let pattern = Pattern(
                    categorySystemKey: categorySystemKeys[groupKey] ?? categoryNames[groupKey],
                    categoryName: categoryNames[groupKey] ?? groupKey,
                    categoryIcon: categoryIcons[groupKey] ?? "tag.fill",
                    categoryColor: categoryColors[groupKey] ?? "#8E8E93",
                    typicalAmount: avgAmount,
                    typicalDay: avgDay,
                    occurrences: cluster.count,
                    maxVariance: maxVariance
                )
                patterns.append(pattern)
            }
        }

        return patterns
    }

    // MARK: - match

    static func match(_ imported: ImportedTransaction, against patterns: [Pattern]) -> RecurringMatch? {
        let cal       = Calendar.current
        let importedDay = cal.component(.day, from: imported.date)

        var bestMatch: (pattern: Pattern, score: Double)? = nil

        for pattern in patterns {
            let pctDiff = abs(imported.amount - pattern.typicalAmount)
                / max(pattern.typicalAmount, 1.0)

            let rawDayDiff = abs(importedDay - pattern.typicalDay)
            let dayDiff    = min(rawDayDiff, 31 - rawDayDiff)   // wraps end-of-month

            // ─────────────────────────────────────────────────────────────
            // Scoring rules (3 tiers, minimum threshold 0.60):
            //
            //  Tier 1 — Data exata  + Valor exato  (<0.5% diff) → 1.00
            //  Tier 2 — Data ±3 dias + Valor exato (<0.5% diff) → 0.85
            //  Tier 3 — Data exata  + Valor próximo (<3% diff)  → 0.60
            //
            //  Abaixo de 0.60 → sem sugestão, usuário associa manualmente.
            // ─────────────────────────────────────────────────────────────
            let score: Double

            let isExactAmount = pctDiff < 0.005   // < 0.5 %
            let isCloseAmount = pctDiff < 0.03    // < 3 %
            let isExactDay    = dayDiff == 0
            let isCloseDay    = dayDiff <= 3      // ±3 dias

            if isExactDay && isExactAmount {
                score = 1.00
            } else if isCloseDay && isExactAmount {
                score = 0.85
            } else if isExactDay && isCloseAmount {
                score = 0.60
            } else {
                continue  // below threshold — skip
            }

            if bestMatch == nil || score > bestMatch!.score {
                bestMatch = (pattern, score)
            }
        }

        guard let best = bestMatch else { return nil }

        return RecurringMatch(
            categorySystemKey: best.pattern.categorySystemKey,
            categoryName:  best.pattern.categoryName,
            categoryIcon:  best.pattern.categoryIcon,
            categoryColor: best.pattern.categoryColor,
            typicalAmount: best.pattern.typicalAmount,
            typicalDay:    best.pattern.typicalDay,
            occurrences:   best.pattern.occurrences,
            confidence:    best.score
        )
    }

    // MARK: - Private helpers

    private static func clusterByAmount(_ txs: [TransactionSnapshot], tolerance: Double) -> [[TransactionSnapshot]] {
        var clusters: [[TransactionSnapshot]] = []

        for tx in txs {
            var placed = false
            for i in 0..<clusters.count {
                let rep = clusters[i][0].amount
                let pctDiff = abs(tx.amount - rep) / max(rep, 1.0)
                if pctDiff <= tolerance {
                    clusters[i].append(tx)
                    placed = true
                    break
                }
            }
            if !placed {
                clusters.append([tx])
            }
        }

        return clusters
    }
}
