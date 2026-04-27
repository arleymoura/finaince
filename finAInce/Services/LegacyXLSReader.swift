import Foundation

enum LegacyXLSReaderError: LocalizedError {
    case openFailed
    case parseFailed
    case noRowsFound

    var errorDescription: String? {
        switch self {
        case .openFailed, .parseFailed:
            return t("csv.errorXLS")
        case .noRowsFound:
            return t("csv.errorColumns")
        }
    }
}

enum LegacyXLSReader {
    static func rows(from data: Data) throws -> [[String]] {
        var bridgeError: NSError?
        guard let parsedRows = LegacyXLSReaderBridge.parseXLSData(data, error: &bridgeError) else {
            if let bridgeError {
                switch LegacyXLSReaderBridgeErrorCode(rawValue: bridgeError.code) {
                case .openFailed:
                    throw LegacyXLSReaderError.openFailed
                case .parseFailed:
                    throw LegacyXLSReaderError.parseFailed
                case .noRowsFound:
                    throw LegacyXLSReaderError.noRowsFound
                case nil:
                    throw LegacyXLSReaderError.parseFailed
                }
            }
            throw LegacyXLSReaderError.parseFailed
        }

        return parsedRows.map { row in
            row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }
}
