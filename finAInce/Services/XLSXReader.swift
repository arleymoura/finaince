import Foundation

// MARK: - libz raw-DEFLATE (windowBits = -15, no header/checksum)
//
// libz.dylib is always loaded in iOS/macOS processes (UIKit/Foundation depend on it).
// We bind to it via @_silgen_name — no explicit Xcode linkage required.
//
// z_stream layout on 64-bit Apple (arm64 / x86_64): 112 bytes
// Matches zlib.h exactly; inflateInit2_ validates sizeof at runtime.
private struct ZStream {
    var next_in:   UnsafePointer<UInt8>?        = nil  //  8  next input byte
    var avail_in:  UInt32                        = 0   //  4  bytes available at next_in
    private var _pad1: UInt32                    = 0   //  4  alignment
    var total_in:  UInt                          = 0   //  8  total bytes read so far
    var next_out:  UnsafeMutablePointer<UInt8>?  = nil  //  8  next output byte
    var avail_out: UInt32                        = 0   //  4  bytes available at next_out
    private var _pad2: UInt32                    = 0   //  4  alignment
    var total_out: UInt                          = 0   //  8  total bytes written so far
    var msg:       UnsafePointer<CChar>?         = nil  //  8  last error message
    var state:     UnsafeMutableRawPointer?      = nil  //  8  internal state (opaque)
    var zalloc:    UnsafeMutableRawPointer?      = nil  //  8  alloc_func (nil = use default)
    var zfree:     UnsafeMutableRawPointer?      = nil  //  8  free_func  (nil = use default)
    var opaque:    UnsafeMutableRawPointer?      = nil  //  8  private data for alloc/free
    var data_type: Int32                         = 0   //  4  best guess about data type
    private var _pad3: UInt32                    = 0   //  4  alignment
    var adler:     UInt                          = 0   //  8  Adler-32 of uncompressed data
    var reserved:  UInt                          = 0   //  8  reserved for future use
    // Total: 112 bytes
}

@_silgen_name("inflateInit2_")
private func _zlibInflateInit2(
    _ strm:        UnsafeMutableRawPointer,
    _ windowBits:  Int32,
    _ version:     UnsafePointer<CChar>,
    _ stream_size: Int32
) -> Int32

@_silgen_name("inflate")
private func _zlibInflate(_ strm: UnsafeMutableRawPointer, _ flush: Int32) -> Int32

@_silgen_name("inflateEnd")
private func _zlibInflateEnd(_ strm: UnsafeMutableRawPointer) -> Int32

// MARK: - Errors

enum XLSXReaderError: LocalizedError {
    case notAZip
    case noWorksheet
    case decompressionFailed
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .notAZip:
            return "Arquivo XLSX inválido ou corrompido."
        case .noWorksheet:
            return "Nenhuma planilha encontrada no arquivo XLSX."
        case .decompressionFailed:
            return "Não foi possível descompactar o arquivo. Tente exportar como CSV."
        case .unsupportedFormat:
            return "Formato de compressão não suportado. Tente exportar como CSV."
        }
    }
}

// MARK: - XLSXReader

/// Reads the first worksheet of an XLSX file (which is a ZIP archive containing XML).
/// No external dependencies — uses libz (raw DEFLATE, windowBits=-15) and XMLParser for XML.
enum XLSXReader {

    // MARK: - Public API

    static func rows(from data: Data) throws -> [[String]] {
        let entries = try centralDirectory(of: data)

        // Shared strings table (optional — some XLSX files inline all strings)
        var sharedStrings: [String] = []
        if let entry = entries.first(where: { $0.name == "xl/sharedStrings.xml" }) {
            if let xmlData = try? extractData(entry: entry, from: data) {
                sharedStrings = parseSharedStrings(xmlData)
            }
        }

        let sheetEntries = entries
            .filter {
                let name = $0.name.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
                return name.hasPrefix("xl/worksheets/") && name.hasSuffix(".xml")
            }
            .sorted { $0.name < $1.name }
        guard !sheetEntries.isEmpty else { throw XLSXReaderError.noWorksheet }

        let parsedSheets = sheetEntries.compactMap { entry -> [[String]]? in
            guard let sheetData = try? extractData(entry: entry, from: data) else { return nil }
            let rows = parseSheet(sheetData, sharedStrings: sharedStrings)
            return rows.isEmpty ? nil : rows
        }

        guard let bestSheet = parsedSheets.max(by: { populatedCellCount($0) < populatedCellCount($1) }) else {
            throw XLSXReaderError.noWorksheet
        }

        return bestSheet
    }

    private static func populatedCellCount(_ rows: [[String]]) -> Int {
        rows.reduce(0) { total, row in
            total + row.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        }
    }

    // MARK: - ZIP central directory

    private struct ZipEntry {
        let name:               String
        let method:             UInt16   // 0 = stored, 8 = deflate
        let compressedSize:     Int
        let uncompressedSize:   Int
        let localHeaderOffset:  Int
    }

    private static func centralDirectory(of data: Data) throws -> [ZipEntry] {
        let n = data.count
        guard n >= 22 else { throw XLSXReaderError.notAZip }

        // Locate End of Central Directory (EOCD) signature 0x06054B50 from the end
        var eocd = -1
        let searchFrom = max(0, n - 65557)
        var i = n - 22
        while i >= searchFrom {
            if data[i] == 0x50, data[i+1] == 0x4B,
               data[i+2] == 0x05, data[i+3] == 0x06 {
                eocd = i; break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw XLSXReaderError.notAZip }

        let entryCount  = Int(le16(data, at: eocd + 10))
        let cdirOffset  = Int(le32(data, at: eocd + 16))

        var pos = cdirOffset
        var entries: [ZipEntry] = []

        for _ in 0..<entryCount {
            guard pos + 46 <= n else { break }
            guard data[pos]   == 0x50, data[pos+1] == 0x4B,
                  data[pos+2] == 0x01, data[pos+3] == 0x02 else { break }

            let method   = le16(data, at: pos + 10)
            let cSize    = Int(le32(data, at: pos + 20))
            let uSize    = Int(le32(data, at: pos + 24))
            let fnLen    = Int(le16(data, at: pos + 28))
            let exLen    = Int(le16(data, at: pos + 30))
            let cmtLen   = Int(le16(data, at: pos + 32))
            let lhOffset = Int(le32(data, at: pos + 42))

            let nameEnd = pos + 46 + fnLen
            guard nameEnd <= n else { break }
            let name = String(bytes: data[(pos + 46)..<nameEnd], encoding: .utf8) ?? ""

            entries.append(ZipEntry(name: name, method: method,
                                    compressedSize: cSize, uncompressedSize: uSize,
                                    localHeaderOffset: lhOffset))
            pos += 46 + fnLen + exLen + cmtLen
        }
        return entries
    }

    // MARK: - Extract single ZIP entry

    private static func extractData(entry: ZipEntry, from data: Data) throws -> Data {
        let n   = data.count
        let off = entry.localHeaderOffset
        guard off + 30 <= n,
              data[off]   == 0x50, data[off+1] == 0x4B,
              data[off+2] == 0x03, data[off+3] == 0x04
        else { throw XLSXReaderError.notAZip }

        let fnLen = Int(le16(data, at: off + 26))
        let exLen = Int(le16(data, at: off + 28))
        let start = off + 30 + fnLen + exLen
        guard start + entry.compressedSize <= n else { throw XLSXReaderError.notAZip }

        let compressed = data.subdata(in: start..<(start + entry.compressedSize))

        switch entry.method {
        case 0:  return compressed                          // stored — no compression
        case 8:  return try inflate(compressed, expected: entry.uncompressedSize)
        default: throw XLSXReaderError.unsupportedFormat
        }
    }

    // MARK: - Raw DEFLATE via libz (windowBits = -15)

    /// ZIP method 8 = raw DEFLATE (RFC 1951) — no zlib header, no Adler-32.
    ///
    /// Apple's Compression.framework only exposes COMPRESSION_ZLIB (RFC 1950),
    /// which requires a 2-byte header AND a 4-byte Adler-32 trailer. ZIP files
    /// omit both, so COMPRESSION_ZLIB fails on strict iOS devices.
    ///
    /// libz.dylib (always present in iOS/macOS processes) supports raw DEFLATE
    /// via inflateInit2_ with windowBits = -15. No Xcode linker flag needed —
    /// the symbol is resolved through the already-loaded dylib.
    private static func inflate(_ raw: Data, expected: Int) throws -> Data {
        // Start with 4× the compressed size or the declared uncompressed size,
        // minimum 64 KB. Grow the buffer if a single inflate pass isn't enough.
        var bufSize = max(expected, raw.count * 4, 65536)
        let Z_OK: Int32         =  0
        let Z_STREAM_END: Int32 =  1
        let Z_NO_FLUSH: Int32   =  0

        while true {
            var dst = Data(count: bufSize)
            var written = 0
            var needsMoreSpace = false

            try raw.withUnsafeBytes { srcBuf in
                let srcPtr = srcBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                try dst.withUnsafeMutableBytes { dstBuf in
                    let dstPtr = dstBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)

                    var strm = ZStream()
                    strm.next_in   = srcPtr
                    strm.avail_in  = UInt32(raw.count)
                    strm.next_out  = dstPtr
                    strm.avail_out = UInt32(bufSize)

                    // windowBits = -15 → raw DEFLATE (no header, no checksum)
                    let initRC = withUnsafeMutableBytes(of: &strm) { p in
                        _zlibInflateInit2(p.baseAddress!, -15, "1.2.11",
                                         Int32(MemoryLayout<ZStream>.size))
                    }
                    guard initRC == Z_OK else { throw XLSXReaderError.decompressionFailed }

                    let rc = withUnsafeMutableBytes(of: &strm) { p in
                        _zlibInflate(p.baseAddress!, Z_NO_FLUSH)
                    }
                    withUnsafeMutableBytes(of: &strm) { p in _ = _zlibInflateEnd(p.baseAddress!) }

                    guard rc == Z_OK || rc == Z_STREAM_END else {
                        throw XLSXReaderError.decompressionFailed
                    }

                    written = bufSize - Int(strm.avail_out)

                    // avail_out == 0 and not Z_STREAM_END → output buffer was full;
                    // double the buffer and retry.
                    if strm.avail_out == 0 && rc != Z_STREAM_END {
                        needsMoreSpace = true
                    }
                }
            }

            if needsMoreSpace {
                bufSize *= 2
                continue
            }

            guard written > 0 else { throw XLSXReaderError.decompressionFailed }
            return dst.prefix(written)
        }
    }

    // MARK: - Little-endian helpers

    private static func le16(_ d: Data, at i: Int) -> UInt16 {
        UInt16(d[i]) | (UInt16(d[i+1]) << 8)
    }
    private static func le32(_ d: Data, at i: Int) -> UInt32 {
        UInt32(d[i]) | (UInt32(d[i+1]) << 8)
            | (UInt32(d[i+2]) << 16) | (UInt32(d[i+3]) << 24)
    }

    // MARK: - Parse xl/sharedStrings.xml

    private static func parseSharedStrings(_ data: Data) -> [String] {
        let delegate = SharedStringsXMLDelegate()
        let parser   = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.result
    }

    // MARK: - Parse xl/worksheets/sheet*.xml

    private static func parseSheet(_ data: Data, sharedStrings: [String]) -> [[String]] {
        let delegate = SheetXMLDelegate(sharedStrings: sharedStrings)
        let parser   = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }
}

// MARK: - XML: Shared Strings

private final class SharedStringsXMLDelegate: NSObject, XMLParserDelegate {
    var result: [String] = []
    private var itemBuffer = ""
    private var textBuffer = ""
    private var inItem = false
    private var inText = false

    func parser(_ parser: XMLParser, didStartElement el: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch el {
        case "si":
            inItem = true
            itemBuffer = ""
        case "t" where inItem:
            inText = true
            textBuffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        if inText { textBuffer += s }
    }

    func parser(_ parser: XMLParser, didEndElement el: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch el {
        case "t" where inText:
            itemBuffer += textBuffer
            textBuffer = ""
            inText = false
        case "si" where inItem:
            result.append(itemBuffer)
            itemBuffer = ""
            inItem = false
        default:
            break
        }
    }
}

// MARK: - XML: Sheet

/// Parses the sheet XML, correctly placing cells by their column reference
/// (e.g. "C4") so that sparse rows with empty cells are preserved.
private final class SheetXMLDelegate: NSObject, XMLParserDelegate {
    let ss: [String]
    var rows: [[String]] = []

    private var row:      [Int: String] = [:]
    private var maxCol    = -1
    private var colIdx    = 0
    private var cellType  = ""
    private var buf       = ""
    private var inV       = false
    private var inIs      = false
    private var inT       = false

    init(sharedStrings: [String]) { ss = sharedStrings }

    func parser(_ parser: XMLParser, didStartElement el: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch el {
        case "row":
            row = [:]; maxCol = -1
        case "c":
            colIdx   = columnIndex(attributes["r"] ?? "")
            cellType = attributes["t"] ?? ""
            buf      = ""
        case "v":
            inV = true
        case "is":
            inIs = true
        case "t" where inIs:
            inT = true; buf = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        if inV || inT { buf += s }
    }

    func parser(_ parser: XMLParser, didEndElement el: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch el {
        case "v":
            inV = false
        case "t" where inIs:
            inT = false
        case "is":
            inIs = false
        case "c":
            let display: String
            if cellType == "s", let i = Int(buf), i < ss.count {
                display = ss[i]
            } else if cellType == "b" {
                display = buf == "1" ? "TRUE" : "FALSE"
            } else {
                display = buf
            }
            row[colIdx] = display
            if colIdx > maxCol { maxCol = colIdx }
        case "row":
            if maxCol >= 0 {
                let arr = (0...maxCol).map { row[$0] ?? "" }
                if !arr.allSatisfy({ $0.isEmpty }) {
                    rows.append(arr)
                }
            }
        default: break
        }
    }

    /// Converts a cell reference like "A", "AB", "C" (letter part of "A1", "AB12") → 0-based Int.
    private func columnIndex(_ ref: String) -> Int {
        var idx = 0
        for scalar in ref.unicodeScalars {
            let v = scalar.value
            if v >= 65 && v <= 90 {       // A–Z
                idx = idx * 26 + Int(v - 64)
            } else if v >= 97 && v <= 122 { // a–z
                idx = idx * 26 + Int(v - 96)
            } else {
                break
            }
        }
        return max(idx - 1, 0)
    }
}
