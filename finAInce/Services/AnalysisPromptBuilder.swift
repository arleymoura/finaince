import Foundation

struct AnalysisPromptBuilder {
    static func buildDeepAnalysisPrompt(
        transactions: [Transaction],
        accounts: [Account],
        goals: [Goal],
        month: Int,
        year: Int,
        currencyCode: String,
        focus: String,
        analysisGoal: String = "Entender em profundidade este insight e gerar recomendacoes praticas."
    ) -> String {
        let scopedTransactions = transactions.filter { transaction in
            let components = Calendar.current.dateComponents([.month, .year], from: transaction.date)
            return components.month == month && components.year == year
        }

        let scopedInsights = InsightEngine.compute(
            transactions: transactions,
            accounts: accounts,
            goals: goals,
            month: month,
            year: year,
            currencyCode: currencyCode
        )

        let insightLines = scopedInsights.prefix(5).map { insight in
            var line = "- \(insight.title): \(insight.body)"
            if let amount = insight.metadata?.amount {
                line += " | valor: \(amount.asCurrency(currencyCode))"
            }
            if let percentage = insight.metadata?.percentage {
                line += " | variacao: \(Int(percentage.rounded()))%"
            }
            return line
        }

        let insightsBlock = insightLines.isEmpty
            ? "- Nenhum insight adicional calculado para este periodo."
            : insightLines.joined(separator: "\n")

        let exportBlock = FinancialAnalysisExporter.buildAnalysisText(
            transactions: transactions,
            accounts: accounts,
            goals: goals,
            selectedMonth: month,
            selectedYear: year,
            adults: 0,
            children: 0,
            currencyCode: currencyCode,
            analysisGoal: analysisGoal
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "MMMM yyyy"
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = 1
        let periodDate = Calendar.current.date(from: dateComponents) ?? Date()
        let periodLabel = formatter.string(from: periodDate).capitalized

        let focusTransactions = scopedTransactions
            .filter { transaction in
                let description = [
                    transaction.placeName,
                    transaction.notes,
                    transaction.category?.name,
                    transaction.subcategory?.name
                ]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")

                return description.contains(focus.lowercased())
            }
            .sorted { $0.date > $1.date }
            .prefix(15)
            .map { transaction in
                let place = transaction.placeName ?? transaction.category?.name ?? "Sem descricao"
                return "- \(transaction.date.formatted(.dateTime.day().month(.abbreviated))) | \(place) | \(transaction.amount.asCurrency(currencyCode))"
            }
            .joined(separator: "\n")

        let focusTransactionsBlock = focusTransactions.isEmpty
            ? "- Nenhuma transacao foi encontrada por correspondencia textual direta com o foco."
            : focusTransactions

        return """
        Quero uma analise financeira profunda com base nos dados abaixo.

        Responda em portugues do Brasil.
        Seja objetivo, pratico e estruturado.
        Nao repita o contexto integralmente; interprete.

        OBJETIVO PRINCIPAL
        - Investigar em profundidade este ponto: \(focus)
        - Periodo principal: \(periodLabel)
        - Tarefa esperada:
          1. explicar o que provavelmente aconteceu
          2. apontar causas-raiz
          3. dizer se isso parece pontual ou tendencia
          4. listar riscos de curto prazo
          5. sugerir acoes concretas e priorizadas

        INSIGHTS JA IDENTIFICADOS PELO APP
        \(insightsBlock)

        TRANSACOES MAIS RELACIONADAS AO FOCO
        \(focusTransactionsBlock)

        CONTEXTO COMPLETO EXPORTADO PELO APP
        \(exportBlock)
        """
    }
}
