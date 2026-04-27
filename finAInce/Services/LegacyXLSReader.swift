import Foundation

@_silgen_name("LegacyXLSCopyRowsJSON")
private func LegacyXLSCopyRowsJSON(
    _ bytes: UnsafePointer<UInt8>,
    _ length: Int,
    _ errorCode: UnsafeMutablePointer<Int32>
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("LegacyXLSFreeCString")
private func LegacyXLSFreeCString(_ pointer: UnsafeMutablePointer<CChar>?)

enum LegacyXLSReaderError: LocalizedError {
    case openFailed
    case parseFailed
    case noRowsFound
    case passwordProtected

    var errorDescription: String? {
        switch self {
        case .passwordProtected:
            return t("csv.errorProtectedXLS")
        case .openFailed, .parseFailed:
            return t("csv.errorXLS")
        case .noRowsFound:
            return t("cvcsv.errorColumns")
        }
    }
}

enum LegacyXLSReader {
    static func rows(from data: Data) throws -> [[String]] {
        var errorCode: Int32 = 0
        let jsonPointer: UnsafeMutablePointer<CChar>? = data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            return LegacyXLSCopyRowsJSON(baseAddress, data.count, &errorCode)
        }

        guard let jsonPointer else {
            switch errorCode {
            case 1:
                throw LegacyXLSReaderError.openFailed
            case 3:
                throw LegacyXLSReaderError.noRowsFound
            case 4:
                throw LegacyXLSReaderError.passwordProtected
            default:
                throw LegacyXLSReaderError.parseFailed
            }
        }

        defer {
            LegacyXLSFreeCString(jsonPointer)
        }

        let jsonData = Data(bytes: jsonPointer, count: strlen(jsonPointer))
        let rawRows = try JSONSerialization.jsonObject(with: jsonData) as? [[String]]
        guard let rawRows else {
            throw LegacyXLSReaderError.parseFailed
        }

        return rawRows.map { row in
            row.map { value in
                value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }
        }
    }
}
