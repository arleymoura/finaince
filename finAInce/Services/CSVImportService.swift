import CryptoKit
import Foundation

// MARK: - Column Map

struct ColumnMap {
    let dateIndex:        Int
    let descriptionIndex: Int
    let amountIndex:      Int
    let headerRowIndex:   Int
    /// Se verdadeiro, o valor na coluna já vem positivo (coluna de débitos separada).
    /// Se falso, valores negativos = débito; positivos = crédito (ignorados).
    let amountIsAlwaysPositive: Bool
}

// MARK: - CSVImportService

enum CSVImportService {

    /// Linhas por lote no processamento chunked.
    static let chunkSize = 100
    // OLE2 armazena nomes de streams em UTF-16LE — não em ASCII/UTF-8.
    // "EncryptedPackage" em UTF-16LE: 45 00 6E 00 63 00 72 00 79 00 70 00 74 00 65 00 64 00 ...
    private static let encryptedOOXMLMarkers: [Data] = [
        "EncryptedPackage".data(using: .utf16LittleEndian) ?? Data(),
        "EncryptionInfo".data(using: .utf16LittleEndian)   ?? Data(),
    ]

    static func passwordKey(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "import.file.password.\(hex)"
    }

    // MARK: - Read file

    static func readFile(from url: URL, password: String? = nil) throws -> [[String]] {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.lowercased()

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw ImportError.emptyFile }

        let magic = data.count >= 4 ? String(format: "%02X%02X%02X%02X", data[0], data[1], data[2], data[3]) : "????"
        let isZIP  = data.count >= 4 && data[0] == 0x50 && data[1] == 0x4B
                                     && data[2] == 0x03 && data[3] == 0x04
        let isOLE2 = data.count >= 4 && data[0] == 0xD0 && data[1] == 0xCF
                                     && data[2] == 0x11 && data[3] == 0xE0

        print("🗂 [Import] url=\(url.lastPathComponent) ext='\(ext)' size=\(data.count) magic=\(magic) isZIP=\(isZIP) isOLE2=\(isOLE2)")

        // OFX — detecta por extensão ou pelos marcadores textuais no conteúdo
        if ext == "ofx" || isOFXContent(data) {
            print("🗂 [Import] → OFX parser")
            let rows = try parseOFX(from: data)
            print("🗂 [Import] ✅ OFX parser returned \(rows.count) rows")
            for (i, r) in rows.prefix(8).enumerated() {
                print("🗂   row[\(i)] (\(r.count) cols): \(r.prefix(3).map { $0.isEmpty ? "∅" : String($0.prefix(30)) })")
            }
            return rows
        }

        if isOLE2, looksLikePasswordProtectedOOXML(data) {
            print("🗂 [Import] 🔒 encrypted OOXML detected")
            let filePasswordKey = passwordKey(for: data)

            guard let password, !password.isEmpty else {
                throw ImportError.passwordRequired(passwordKey: filePasswordKey, fileName: url.lastPathComponent)
            }

            do {
                let rows = try ProtectedXLSXReader.rows(from: data, password: password)
                print("🗂 [Import] ✅ ProtectedXLSXReader returned \(rows.count) rows")
                for (i, r) in rows.prefix(8).enumerated() {
                    print("🗂   row[\(i)] (\(r.count) cols): \(r.prefix(4).map { $0.isEmpty ? "∅" : String($0.prefix(20)) })")
                }
                return rows
            } catch let error as ProtectedXLSXReaderError {
                switch error {
                case .invalidPassword:
                    throw ImportError.invalidPassword(passwordKey: filePasswordKey, fileName: url.lastPathComponent)
                case .unsupportedEncryption:
                    throw ImportError.xlsxFailed(error.localizedDescription)
                default:
                    throw ImportError.xlsxFailed(error.localizedDescription)
                }
            }
        }

        if isOLE2 {
            print("🗂 [Import] → LegacyXLSReader (OLE2/.xls)")
            do {
                let rows = try LegacyXLSReader.rows(from: data)
                print("🗂 [Import] ✅ LegacyXLSReader returned \(rows.count) rows")
                for (i, r) in rows.prefix(8).enumerated() {
                    print("🗂   row[\(i)] (\(r.count) cols): \(r.prefix(4).map { $0.isEmpty ? "∅" : String($0.prefix(20)) })")
                }
                return rows
            } catch {
                print("🗂 [Import] ❌ LegacyXLSReader threw: \(error.localizedDescription)")
                throw ImportError.xlsFailed(error.localizedDescription)
            }
        }

        if isZIP || ext == "xlsx" {
            print("🗂 [Import] → XLSXReader")
            do {
                let rows = try XLSXReader.rows(from: data)
                print("🗂 [Import] ✅ XLSXReader returned \(rows.count) rows")
                for (i, r) in rows.prefix(8).enumerated() {
                    print("🗂   row[\(i)] (\(r.count) cols): \(r.prefix(4).map { $0.isEmpty ? "∅" : String($0.prefix(20)) })")
                }
                return rows
            } catch let e as XLSXReaderError {
                print("🗂 [Import] ❌ XLSXReader threw: \(e.localizedDescription)")
                // ZIP/XLSX binary data will never parse as meaningful CSV text —
                // throw the real error immediately instead of falling back and
                // confusing the user with a "cannot identify columns" message.
                throw ImportError.xlsxFailed(e.localizedDescription)
            }
        }

        if ext == "xls" {
            if let rows = parseRowsFromTextData(data), !rows.isEmpty { return rows }
            print("🗂 [Import] → LegacyXLSReader (.xls fallback)")
            do {
                let rows = try LegacyXLSReader.rows(from: data)
                print("🗂 [Import] ✅ LegacyXLSReader returned \(rows.count) rows")
                for (i, r) in rows.prefix(8).enumerated() {
                    print("🗂   row[\(i)] (\(r.count) cols): \(r.prefix(4).map { $0.isEmpty ? "∅" : String($0.prefix(20)) })")
                }
                return rows
            } catch {
                print("🗂 [Import] ❌ LegacyXLSReader threw: \(error.localizedDescription)")
                throw ImportError.xlsFailed(error.localizedDescription)
            }
        }

        print("🗂 [Import] → text parser")
        return try readTextRows(from: url)
    }

    private static func readTextRows(from url: URL) throws -> [[String]] {
        let raw: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            raw = utf8
        } else if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            raw = latin1
        } else {
            throw ImportError.encodingFailed
        }

        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyFile
        }

        return parseRows(raw)
    }

    private static func parseRowsFromTextData(_ data: Data) -> [[String]]? {
        let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return parseRows(raw)
    }

    private static func looksLikePasswordProtectedOOXML(_ data: Data) -> Bool {
        encryptedOOXMLMarkers.allSatisfy { marker in
            !marker.isEmpty && data.range(of: marker) != nil
        }
    }

    // MARK: - OFX parser (SGML 1.x e XML 2.x)

    /// Retorna `true` se os primeiros bytes do arquivo contêm marcadores OFX.
    private static func isOFXContent(_ data: Data) -> Bool {
        let sample = data.prefix(512)
        guard let text = String(data: sample, encoding: .utf8)
                      ?? String(data: sample, encoding: .isoLatin1) else { return false }
        let upper = text.uppercased()
        return upper.contains("OFXHEADER:") || upper.contains("<OFX>") || upper.contains("<?OFX")
    }

    /// Converte um arquivo OFX em `[[String]]` com header `["Data","Descrição","Valor"]`.
    /// Funciona tanto com OFX 1.x (SGML, sem fechamento de tags) quanto OFX 2.x (XML).
    private static func parseOFX(from data: Data) throws -> [[String]] {
        guard let content = String(data: data, encoding: .utf8)
                         ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.encodingFailed
        }

        // Header compatível com detectColumns() — palavras-chave reconhecidas pelo parser
        var rows: [[String]] = [["Data", "Descrição", "Valor"]]

        var inTransaction = false
        var date          = ""
        var memo          = ""
        var name          = ""
        var amount        = ""

        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")
            .components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let upper = trimmed.uppercased()

            // ── Abertura de transação ─────────────────────────────────────
            if upper.hasPrefix("<STMTTRN>") {
                inTransaction = true
                date = ""; memo = ""; name = ""; amount = ""
                continue
            }

            // ── Fechamento de transação ───────────────────────────────────
            if upper.hasPrefix("</STMTTRN>") {
                if inTransaction, !date.isEmpty, !amount.isEmpty {
                    // Prefere NAME; cai para MEMO; usa placeholder se ambos vazios
                    let description: String
                    let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let m = memo.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !n.isEmpty && !m.isEmpty && n.lowercased() != m.lowercased() {
                        description = "\(n) – \(m)"
                    } else {
                        description = n.isEmpty ? m : n
                    }
                    rows.append([date, description, amount])
                }
                inTransaction = false
                continue
            }

            guard inTransaction else { continue }

            // ── Campos da transação ───────────────────────────────────────
            if let v = ofxTagValue(trimmed, tag: "DTPOSTED") {
                date = formatOFXDate(v) ?? v
            } else if let v = ofxTagValue(trimmed, tag: "TRNAMT") {
                amount = v
            } else if let v = ofxTagValue(trimmed, tag: "NAME") {
                name = v
            } else if let v = ofxTagValue(trimmed, tag: "MEMO") {
                memo = v
            }
        }

        guard rows.count > 1 else { throw ImportError.emptyFile }
        return rows
    }

    /// Extrai o valor de uma tag OFX tanto no formato SGML (`<TAG>valor`)
    /// quanto no formato XML (`<TAG>valor</TAG>`).
    private static func ofxTagValue(_ line: String, tag: String) -> String? {
        let openTag = "<\(tag)>"
        guard line.uppercased().hasPrefix(openTag) else { return nil }
        var value = String(line.dropFirst(openTag.count))
        // Remove a tag de fechamento se presente (OFX 2.x / XML)
        if let closeRange = value.range(of: "</\(tag)>", options: .caseInsensitive) {
            value = String(value[..<closeRange.lowerBound])
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converte data OFX (`YYYYMMDD` ou `YYYYMMDDHHmmss[.xxx][+offset]`) para `dd/MM/yyyy`.
    private static func formatOFXDate(_ raw: String) -> String? {
        let digits = String(raw.filter(\.isNumber).prefix(8))
        guard digits.count == 8 else { return nil }
        let year  = digits.prefix(4)
        let month = digits.dropFirst(4).prefix(2)
        let day   = digits.dropFirst(6).prefix(2)
        return "\(day)/\(month)/\(year)"
    }

    // MARK: - Parse raw text → matrix

    static func parseRows(_ raw: String) -> [[String]] {
        // Se parece com HTML (XLS do Santander/BBVA/CaixaBank exporta HTML com extensão .xls)
        let trimmedStart = raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200).lowercased()
        if trimmedStart.contains("<html") || trimmedStart.contains("<table") || trimmedStart.contains("<!doctype") {
            let htmlRows = parseHTMLTable(raw)
            if !htmlRows.isEmpty { return htmlRows }
        }

        // CSV / TSV / semicolon-separated. Bank exports often start with metadata
        // rows, so detect the delimiter across a sample instead of the first line.
        let lines = raw.components(separatedBy: .newlines)
        let delimiter = detectDelimiter(in: lines)

        return lines.compactMap { line -> [String]? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let fields = parseCSVLine(trimmed, delimiter: delimiter)
            return fields.isEmpty ? nil : fields
        }
    }

    // MARK: - HTML table parser (para XLS que são na verdade HTML)

    static func parseHTMLTable(_ html: String) -> [[String]] {
        var rows: [[String]] = []

        // Usa regex simples para extrair linhas e células
        guard let rowRegex = try? NSRegularExpression(
            pattern: "<tr[^>]*>(.*?)</tr>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ),
        let cellRegex = try? NSRegularExpression(
            pattern: "<t[dh][^>]*>(.*?)</t[dh]>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        let nsHTML = html as NSString
        let rowMatches = rowRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for rowMatch in rowMatches {
            let rowContent = nsHTML.substring(with: rowMatch.range(at: 1))
            let cellMatches = cellRegex.matches(in: rowContent,
                                                range: NSRange(location: 0, length: (rowContent as NSString).length))
            let cells = cellMatches.map { match -> String in
                let raw = (rowContent as NSString).substring(with: match.range(at: 1))
                return stripHTML(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !cells.isEmpty && !cells.allSatisfy({ $0.isEmpty }) {
                rows.append(cells)
            }
        }

        return rows
    }

    /// Remove tags HTML e decodifica entidades comuns
    private static func stripHTML(_ html: String) -> String {
        var s = html
        // Remove tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        // Decodifica entidades comuns
        s = s
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
        return s
    }

    // MARK: - Delimiter detection

    private static func detectDelimiter(in lines: [String]) -> Character {
        let candidates: [Character] = [";", "\t", "|", ","]
        let nonEmptyLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(80)

        let scores = candidates.map { delimiter -> (delimiter: Character, score: Int) in
            let counts = nonEmptyLines.map { line in line.filter { $0 == delimiter }.count }
            let tableRows = counts.filter { $0 >= 2 }.count
            let totalSeparators = counts.reduce(0, +)
            return (delimiter, tableRows * 100 + totalSeparators)
        }

        return scores.max(by: { $0.score < $1.score })?.delimiter ?? ","
    }

    // MARK: - RFC-4180 CSV line parser

    private static func parseCSVLine(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            switch char {
            case "\"":
                inQuotes.toggle()
            case delimiter where !inQuotes:
                fields.append(current.trimmingCharacters(in: .whitespaces)
                                     .replacingOccurrences(of: "\"", with: ""))
                current = ""
            default:
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces)
                             .replacingOccurrences(of: "\"", with: ""))
        return fields
    }

    // MARK: - Column detection (heuristic)

    static func detectColumns(in rows: [[String]]) -> ColumnMap? {
        print("🔍 [detectColumns] total rows=\(rows.count), first row cols=\(rows.first?.count ?? 0)")
        for (index, row) in rows.prefix(8).enumerated() {
            let preview = row.enumerated().map { "[\($0.offset)]=\($0.element.isEmpty ? "∅" : $0.element)" }.joined(separator: " | ")
            print("🔍 [detectColumns] row[\(index)] \(preview)")
        }
        for (rowIndex, headers) in rows.enumerated() {
            if let map = detectColumns(inHeader: headers, headerRowIndex: rowIndex) {
                let headerPreview = headers.enumerated().map { "[\($0.offset)]=\($0.element.isEmpty ? "∅" : $0.element)" }.joined(separator: " | ")
                print("🔍 [detectColumns] ✅ header match at row \(rowIndex): date=\(map.dateIndex) desc=\(map.descriptionIndex) amount=\(map.amountIndex) positive=\(map.amountIsAlwaysPositive)")
                print("🔍 [detectColumns] header row raw: \(headerPreview)")
                return map
            }
        }

        if let santander = inferSantanderColumns(in: rows) {
            print("🔍 [detectColumns] ✅ Santander heuristic matched")
            return santander
        }

        if let inferred = inferColumnsFromData(in: rows) {
            print("🔍 [detectColumns] ✅ inferred from data")
            return inferred
        }

        guard let headers = rows.first, headers.count >= 3 else {
            print("🔍 [detectColumns] ❌ nil — rows.first=\(rows.first?.count ?? -1) cols")
            return nil
        }

        guard positionalFallbackLooksLikeTransactions(in: rows) else {
            print("🔍 [detectColumns] ❌ positional fallback rejected — rows do not look like bank transactions")
            return nil
        }

        print("🔍 [detectColumns] ⚠️ positional fallback")
        return ColumnMap(
            dateIndex: 0,
            descriptionIndex: 1,
            amountIndex: 2,
            headerRowIndex: 0,
            amountIsAlwaysPositive: false
        )
    }

    private static func detectColumns(inHeader headers: [String], headerRowIndex: Int) -> ColumnMap? {
        let h = headers.map { $0.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: nil)
        }

        // ── Date ──────────────────────────────────────────────────────────
        let dateKw = ["fecha", "date", "data", "fec", "dat"]
        let isDateColumn: (String) -> Bool = { col in
            dateKw.contains { col.contains($0) }
        }
        let dateIdx = h.firstIndex(where: isDateColumn)

        // ── Description ───────────────────────────────────────────────────
        // Tier 1: colunas de nome de estabelecimento / transação (maior prioridade)
        let descHighKw = ["nome do local", "nome da transac", "nome comercial",
                          "estabelecimento", "merchant", "comercio", "comerciante",
                          "local", "loja"]
        // Tier 2: colunas genéricas de descrição / histórico
        let descLowKw  = ["concepto", "descripci", "descripcion", "descrição", "descricao",
                          "descri", "operaci", "operac", "description", "details",
                          "histor", "historico", "histórico", "memo", "referenc",
                          "concept", "benefi", "detalhe", "detalh", "lancamento",
                          "lançamento", "nome", "transac", "transação"]
        let descIdx = h.firstIndex { col in
            !isDateColumn(col) && descHighKw.contains { col.contains($0) }
        } ?? h.firstIndex { col in
            !isDateColumn(col) && descLowKw.contains { col.contains($0) }
        }

        // ── Amount ────────────────────────────────────────────────────────
        // Prioridade 1: colunas explicitamente separadas de débito/saída.
        let debitKw = ["debito", "debitos", "débito", "débitos", "cargo", "cargos",
                       "saida", "saidas", "saída", "saídas", "despesa", "despesas",
                       "pagamento", "pagamentos", "debit", "debits", "withdrawn",
                       "withdrawal", "withdrawals", "expense", "expenses", "payment"]
        let debitIdx = h.firstIndex { col in
            !isDateColumn(col) && debitKw.contains { col.contains($0) }
        }

        // Prioridade 2: coluna genérica de valor/importe (exclui data e saldo).
        let balanceKw = ["saldo", "balance", "disponib"]
        let amountKw  = ["importe", "amount", "valor", "monto", "montante", "quantia", "total",
                         "moviment", "movement", "transaction", "transacao", "transação"]
        let amountIdx = h.firstIndex { col in
            amountKw.contains { col.contains($0) } &&
            !isDateColumn(col) &&
            !balanceKw.contains { col.contains($0) }
        }

        let (finalAmountIdx, alwaysPositive): (Int?, Bool)
        if let di = debitIdx {
            (finalAmountIdx, alwaysPositive) = (di, false)
        } else if let ai = amountIdx {
            (finalAmountIdx, alwaysPositive) = (ai, false)
        } else {
            (finalAmountIdx, alwaysPositive) = (nil, false)
        }

        guard let di = dateIdx, let dsi = descIdx, let ai = finalAmountIdx else { return nil }
        guard Set([di, dsi, ai]).count == 3 else { return nil }
        return ColumnMap(
            dateIndex: di,
            descriptionIndex: dsi,
            amountIndex: ai,
            headerRowIndex: headerRowIndex,
            amountIsAlwaysPositive: alwaysPositive
        )
    }

    private struct ColumnScore {
        var date = 0
        var amount = 0
        var text = 0
    }

    private static func inferColumnsFromData(in rows: [[String]]) -> ColumnMap? {
        let maxColumnCount = rows.map(\.count).max() ?? 0
        guard maxColumnCount >= 3 else { return nil }

        for startIndex in rows.indices {
            let sampleRows = Array(rows.dropFirst(startIndex).prefix(40))
            let scores = scoreColumns(in: sampleRows, maxColumnCount: maxColumnCount)

            guard let dateIndex = bestIndex(in: scores, keyPath: \.date, minimum: 2),
                  let amountIndex = bestIndex(in: scores, keyPath: \.amount, minimum: 2, excluding: [dateIndex]),
                  let descriptionIndex = bestIndex(
                    in: scores,
                    keyPath: \.text,
                    minimum: 2,
                    excluding: [dateIndex, amountIndex]
                  ) else { continue }

            let headerRowIndex = max(startIndex - 1, 0)
            let dataRows = Array(rows.dropFirst(startIndex))
            return ColumnMap(
                dateIndex: dateIndex,
                descriptionIndex: descriptionIndex,
                amountIndex: amountIndex,
                headerRowIndex: headerRowIndex,
                amountIsAlwaysPositive: treatsPositiveAmountsAsDebits(in: dataRows, amountIndex: amountIndex)
            )
        }

        return nil
    }

    private static func inferSantanderColumns(in rows: [[String]]) -> ColumnMap? {
        if let headerMap = inferSantanderBrazilHeaderColumns(in: rows) {
            return headerMap
        }

        for startIndex in rows.indices {
            let sampleRows = Array(rows.dropFirst(startIndex).prefix(20))
            let matches = sampleRows.filter { row in
                row.count >= 5 &&
                parseDate(row[0]) != nil &&
                parseDate(row[1]) != nil &&
                looksLikeDescription(row[2]) &&
                parseAmount(row[3]) != nil &&
                parseAmount(row[4]) != nil
            }

            guard matches.count >= 2 else { continue }
            let dataRows = Array(rows.dropFirst(startIndex))
            return ColumnMap(
                dateIndex: 0,
                descriptionIndex: 2,
                amountIndex: 3,
                headerRowIndex: max(startIndex - 1, 0),
                amountIsAlwaysPositive: treatsPositiveAmountsAsDebits(in: dataRows, amountIndex: 3)
            )
        }

        return nil
    }

    private static func inferSantanderBrazilHeaderColumns(in rows: [[String]]) -> ColumnMap? {
        for (rowIndex, row) in rows.enumerated() {
            let normalized = row.map(normalizeHeaderToken)
            guard normalized.contains(where: { $0 == "data" }),
                  normalized.contains(where: { $0.contains("descricao") }),
                  normalized.contains(where: { $0.contains("debito") }),
                  normalized.contains(where: { $0.contains("credito") || $0.contains("saldo") }) else {
                continue
            }

            guard let dateIndex = normalized.firstIndex(where: { $0 == "data" }),
                  let descriptionIndex = normalized.firstIndex(where: { $0.contains("descricao") }),
                  let debitIndex = normalized.firstIndex(where: { $0.contains("debito") }) else {
                continue
            }

            let dataRows = Array(rows.dropFirst(rowIndex + 1))
            guard santanderBrazilDataRowsMatch(dataRows, dateIndex: dateIndex, descriptionIndex: descriptionIndex, debitIndex: debitIndex) else {
                continue
            }

            return ColumnMap(
                dateIndex: dateIndex,
                descriptionIndex: descriptionIndex,
                amountIndex: debitIndex,
                headerRowIndex: rowIndex,
                amountIsAlwaysPositive: treatsPositiveAmountsAsDebits(in: dataRows, amountIndex: debitIndex)
            )
        }

        return nil
    }

    private static func santanderBrazilDataRowsMatch(
        _ rows: [[String]],
        dateIndex: Int,
        descriptionIndex: Int,
        debitIndex: Int
    ) -> Bool {
        let maxIndex = max(dateIndex, descriptionIndex, debitIndex)
        let matches = rows.prefix(40).filter { row in
            row.count > maxIndex &&
            parseDate(row[dateIndex]) != nil &&
            looksLikeDescription(row[descriptionIndex]) &&
            parseAmount(row[debitIndex]) != nil
        }

        return matches.count >= 2
    }

    nonisolated private static func normalizeHeaderToken(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func positionalFallbackLooksLikeTransactions(in rows: [[String]]) -> Bool {
        let sampleRows = rows.dropFirst().prefix(12)
        let matches = sampleRows.filter { row in
            row.count >= 3 &&
            parseDate(row[0]) != nil &&
            looksLikeDescription(row[1]) &&
            parseAmount(row[2]) != nil
        }

        return matches.count >= 2
    }

    private static func scoreColumns(in rows: [[String]], maxColumnCount: Int) -> [ColumnScore] {
        var scores = Array(repeating: ColumnScore(), count: maxColumnCount)

        for row in rows {
            for columnIndex in 0..<min(row.count, maxColumnCount) {
                let value = row[columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }

                let parsedDate = parseDate(value)
                let parsedAmount = parseAmount(value)

                if parsedDate != nil {
                    scores[columnIndex].date += 1
                }

                if let amount = parsedAmount, parsedDate == nil {
                    scores[columnIndex].amount += amount < 0 ? 3 : 1
                }

                if looksLikeDescription(value) {
                    scores[columnIndex].text += 1
                }
            }
        }

        return scores
    }

    private static func bestIndex(
        in scores: [ColumnScore],
        keyPath: KeyPath<ColumnScore, Int>,
        minimum: Int,
        excluding excludedIndexes: Set<Int> = []
    ) -> Int? {
        scores.indices
            .filter { !excludedIndexes.contains($0) && scores[$0][keyPath: keyPath] >= minimum }
            .max { scores[$0][keyPath: keyPath] < scores[$1][keyPath: keyPath] }
    }

    private static func looksLikeDescription(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }
        guard parseDate(trimmed) == nil, parseAmount(trimmed) == nil else { return false }
        return trimmed.rangeOfCharacter(from: .letters) != nil
    }

    // MARK: - Extract transactions (chunked, pure Swift)

    static func extractTransactions(
        from rows: [[String]],
        columns: ColumnMap
    ) -> [ImportedTransaction] {
        let dataRows = Array(rows.dropFirst(columns.headerRowIndex + 1)) // pula preâmbulo + header
        var all: [ImportedTransaction] = []

        // Divide em chunks e processa cada um
        let chunks = stride(from: 0, to: dataRows.count, by: chunkSize).map {
            Array(dataRows[$0 ..< min($0 + chunkSize, dataRows.count)])
        }

        let maxIdx = max(columns.dateIndex, columns.descriptionIndex, columns.amountIndex)
        let importPositiveAmounts = columns.amountIsAlwaysPositive || treatsPositiveAmountsAsDebits(
            in: dataRows,
            amountIndex: columns.amountIndex
        )

        print("🧾 [extractTransactions] headerRowIndex=\(columns.headerRowIndex) dateIndex=\(columns.dateIndex) descIndex=\(columns.descriptionIndex) amountIndex=\(columns.amountIndex) importPositiveAmounts=\(importPositiveAmounts)")
        if rows.indices.contains(columns.headerRowIndex) {
            let header = rows[columns.headerRowIndex]
            let headerPreview = header.enumerated().map { "[\($0.offset)]=\($0.element.isEmpty ? "∅" : $0.element)" }.joined(separator: " | ")
            print("🧾 [extractTransactions] header row: \(headerPreview)")
        }

        var debugPrinted = 0
        for chunk in chunks {
            for row in chunk {
                guard row.count > maxIdx else { continue }

                let rawDate   = row[columns.dateIndex].trimmingCharacters(in: .whitespaces)
                let rawDesc   = row[columns.descriptionIndex].trimmingCharacters(in: .whitespaces)
                let rawAmount = resolvedAmountField(in: row, preferredIndex: columns.amountIndex).trimmingCharacters(in: .whitespaces)

                if debugPrinted < 12 {
                    let rowPreview = row.enumerated().map { "[\($0.offset)]=\($0.element.isEmpty ? "∅" : $0.element)" }.joined(separator: " | ")
                    print("🧾 [extractTransactions] row sample: \(rowPreview)")
                    print("🧾 [extractTransactions] -> rawDate='\(rawDate)' rawDesc='\(rawDesc)' rawAmount='\(rawAmount)'")
                    debugPrinted += 1
                }

                guard !rawDate.isEmpty, !rawAmount.isEmpty else { continue }
                guard let amount = parseAmount(rawAmount) else { continue }
                guard let date   = parseDate(rawDate)     else { continue }

                // Filtra créditos: CSVs assinados usam negativos para débitos.
                // Alguns bancos exportam apenas despesas como valores positivos.
                if importPositiveAmounts {
                    guard amount > 0 else { continue }
                } else {
                    guard amount < 0 else { continue }
                }

                all.append(ImportedTransaction(
                    rawDescription: rawDesc,
                    amount: abs(amount),
                    date: date
                ))
            }
        }

        return all
    }

    private static func resolvedAmountField(in row: [String], preferredIndex: Int) -> String {
        if row.indices.contains(preferredIndex) {
            let preferred = row[preferredIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if parseAmount(preferred) != nil {
                return preferred
            }
        }

        let nearbyIndexes = [preferredIndex - 2, preferredIndex - 1, preferredIndex + 1, preferredIndex + 2]
            .filter { row.indices.contains($0) }

        for index in nearbyIndexes {
            let candidate = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard parseAmount(candidate) != nil else { continue }
            return candidate
        }

        return row.indices.contains(preferredIndex) ? row[preferredIndex] : ""
    }

    private static func treatsPositiveAmountsAsDebits(in rows: [[String]], amountIndex: Int) -> Bool {
        var positiveCount = 0
        var negativeCount = 0

        for row in rows where row.count > amountIndex {
            guard let amount = parseAmount(row[amountIndex]) else { continue }
            if amount > 0 {
                positiveCount += 1
            } else if amount < 0 {
                negativeCount += 1
            }
        }

        return positiveCount > 0 && negativeCount == 0
    }

    // MARK: - Amount parsing

    /// Converte string monetária (qualquer formato) em Double.
    /// Retorna positivo para créditos e negativo para débitos.
    static func parseAmount(_ string: String) -> Double? {
        var s = string.trimmingCharacters(in: .whitespaces)

        // Remove símbolos de moeda
        for sym in ["EUR", "R$", "BRL", "USD", "GBP", "€", "$", "£", "¥"] {
            s = s.replacingOccurrences(of: sym, with: "", options: .caseInsensitive)
        }
        s = s.trimmingCharacters(in: .whitespaces)

        // Detecta sinal negativo (pode vir no início ou no fim: "-1,20" ou "1,20-")
        // Alguns exports usam o sinal Unicode U+2212 em vez do hífen ASCII.
        let minusSigns = ["-", "−"]
        let isNegative = minusSigns.contains { s.hasPrefix($0) || s.hasSuffix($0) }
        for minus in minusSigns {
            s = s.replacingOccurrences(of: minus, with: "")
        }
        s = s.trimmingCharacters(in: .whitespaces)

        guard !s.isEmpty else { return nil }

        let hasDot   = s.contains(".")
        let hasComma = s.contains(",")

        if hasDot && hasComma {
            // Determina qual é o separador decimal pelo último separador
            let dotIdx   = s.lastIndex(of: ".")!
            let commaIdx = s.lastIndex(of: ",")!
            if dotIdx > commaIdx {
                // US: 1,234.56 → remove comma
                s = s.replacingOccurrences(of: ",", with: "")
            } else {
                // Europeu: 1.234,56 → remove dot, troca comma por dot
                s = s.replacingOccurrences(of: ".", with: "")
                     .replacingOccurrences(of: ",", with: ".")
            }
        } else if hasComma {
            // Só vírgula: decimal (1,20) ou milhar (1,200)?
            let afterComma = String(s[s.index(after: s.lastIndex(of: ",")!)...])
            s = afterComma.count <= 2
                ? s.replacingOccurrences(of: ",", with: ".")  // decimal
                : s.replacingOccurrences(of: ",", with: "")   // milhar
        }

        guard let value = Double(s), value != 0 else { return nil }
        return isNegative ? -value : value
    }

    // MARK: - Date parsing

    static func parseDate(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespaces)

        if let excelDate = parseExcelSerialDate(s) {
            return excelDate
        }

        // ISO 8601
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let d = iso.date(from: s) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")

        for fmt in ["dd/MM/yyyy", "dd/MM/yy", "d/M/yyyy", "d/M/yy",
                    "MM/dd/yyyy", "MM/dd/yy",
                    "dd-MM-yyyy", "dd-MM-yy",
                    "yyyy/MM/dd", "yyyy-MM-d"] {
            df.dateFormat = fmt
            if let d = df.date(from: s) { return d }
        }
        return nil
    }

    private static func parseExcelSerialDate(_ string: String) -> Date? {
        let normalized = string.replacingOccurrences(of: ",", with: ".")
        guard let serial = Double(normalized), serial >= 20000, serial < 100000 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 1899
        components.month = 12
        components.day = 30
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.nanosecond = 0

        guard let baseDate = components.date else { return nil }
        return calendar.date(
            byAdding: .day,
            value: Int(serial.rounded(.down)),
            to: baseDate
        )
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case accessDenied
        case emptyFile
        case encodingFailed
        case columnDetectionFailed
        case xlsxFailed(String)
        case xlsFailed(String)
        case biff8NotSupported
        case passwordProtectedXLSX
        case passwordRequired(passwordKey: String, fileName: String)
        case invalidPassword(passwordKey: String, fileName: String)

        var errorDescription: String? {
            switch self {
            case .accessDenied:          return t("csv.errorAccess")
            case .emptyFile:             return t("csv.errorEmpty")
            case .encodingFailed:        return t("csv.errorEncoding")
            case .columnDetectionFailed: return t("csv.errorColumns")
            case .xlsxFailed(let msg):   return msg
            case .xlsFailed(let msg):    return msg
            case .biff8NotSupported:     return t("csv.errorXLS")
            case .passwordProtectedXLSX: return t("csv.errorProtectedXLSX")
            case .passwordRequired:      return t("csv.errorProtectedXLSX")
            case .invalidPassword:       return t("csv.passwordWrong")
            }
        }
    }
}
