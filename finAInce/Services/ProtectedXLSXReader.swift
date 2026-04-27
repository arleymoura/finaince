import CommonCrypto
import CryptoKit
import Foundation

enum ProtectedXLSXReaderError: LocalizedError {
    case notEncrypted
    case invalidFormat
    case unsupportedEncryption
    case invalidPassword
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .notEncrypted, .invalidFormat, .decryptionFailed:
            return t("csv.errorXLSX")
        case .unsupportedEncryption:
            return t("csv.errorProtectedXLSXUnsupported")
        case .invalidPassword:
            return t("csv.passwordWrong")
        }
    }
}

enum ProtectedXLSXReader {
    private struct EncryptionPackage {
        let encryptionInfo: Data
        let encryptedPackage: Data
    }

    private struct AgileKeyData {
        let saltValue: Data
        let hashAlgorithm: String
    }

    private struct AgileEncryptedKey {
        let spinCount: UInt32
        let encryptedKeyValue: Data
        let saltValue: Data
        let hashAlgorithm: String
        let keyBits: Int
    }

    private struct AgileInfo {
        let keyData: AgileKeyData
        let encryptedKey: AgileEncryptedKey
    }

    static func rows(from data: Data, password: String) throws -> [[String]] {
        print("🔐 [ProtectedXLSX] extracting OLE2 streams (\(data.count) bytes)")
        let streams: EncryptionPackage
        do {
            streams = try extractStreams(from: data)
        } catch {
            print("🔐 [ProtectedXLSX] ❌ extractStreams failed: \(error)")
            throw error
        }
        print("🔐 [ProtectedXLSX] ✅ streams extracted — encryptionInfo=\(streams.encryptionInfo.count)B encryptedPackage=\(streams.encryptedPackage.count)B")

        print("🔐 [ProtectedXLSX] parsing AgileInfo XML")
        let agileInfo: AgileInfo
        do {
            agileInfo = try parseAgileInfo(from: streams.encryptionInfo)
        } catch {
            print("🔐 [ProtectedXLSX] ❌ parseAgileInfo failed: \(error)")
            throw error
        }
        print("🔐 [ProtectedXLSX] ✅ AgileInfo — keyHash=\(agileInfo.keyData.hashAlgorithm) keyHash=\(agileInfo.encryptedKey.hashAlgorithm) spinCount=\(agileInfo.encryptedKey.spinCount) keyBits=\(agileInfo.encryptedKey.keyBits)")

        print("🔐 [ProtectedXLSX] decrypting package")
        let decryptedData: Data
        do {
            decryptedData = try decryptPackage(streams.encryptedPackage, agileInfo: agileInfo, password: password)
        } catch {
            print("🔐 [ProtectedXLSX] ❌ decryptPackage failed: \(error)")
            throw error
        }
        print("🔐 [ProtectedXLSX] ✅ decrypted \(decryptedData.count) bytes — parsing XLSX")

        do {
            let result = try XLSXReader.rows(from: decryptedData)
            print("🔐 [ProtectedXLSX] ✅ parsed \(result.count) rows")
            return result
        } catch {
            print("🔐 [ProtectedXLSX] ❌ XLSXReader failed (likely wrong password): \(error)")
            throw ProtectedXLSXReaderError.invalidPassword
        }
    }

    // MARK: - Pure Swift CFB (Compound File Binary / OLE2) parser
    //
    // Replaces the old libxls-based ObjC interop. libxls uses ole2_open_buffer
    // which is designed for BIFF/XLS and fails on encrypted-XLSX OLE2 containers.
    // This parser follows the MS-CFB spec directly and extracts the two streams
    // we need: "EncryptionInfo" and "EncryptedPackage".

    private static func extractStreams(from data: Data) throws -> EncryptionPackage {
        // --- Validate CFB magic ---
        let magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        guard data.count >= 512, data.prefix(8).elementsEqual(magic) else {
            throw ProtectedXLSXReaderError.invalidFormat
        }

        // --- Parse header ---
        let sectorSize     = 1 << Int(readUInt16LE(in: data, offset: 30))   // typically 512
        let miniSectorSize = 1 << Int(readUInt16LE(in: data, offset: 32))   // typically 64
        let firstDirSector = Int(readUInt32LE(in: data, offset: 48))
        let miniCutoff     = Int(readUInt32LE(in: data, offset: 56))        // typically 4096
        let firstMiniFATSec = readUInt32LE(in: data, offset: 60)
        let firstDIFATSec   = readUInt32LE(in: data, offset: 68)
        let difatSecCount   = Int(readUInt32LE(in: data, offset: 72))

        let FREESECT:   UInt32 = 0xFFFF_FFFF
        let ENDOFCHAIN: UInt32 = 0xFFFF_FFFE

        guard sectorSize >= 64, sectorSize <= 65536 else {
            throw ProtectedXLSXReaderError.invalidFormat
        }

        // --- Collect FAT sector numbers from the DIFAT ---
        var fatSectorList: [UInt32] = []
        for i in 0..<109 {
            let entry = readUInt32LE(in: data, offset: 76 + i * 4)
            if entry == FREESECT || entry == ENDOFCHAIN { break }
            fatSectorList.append(entry)
        }
        if difatSecCount > 0, firstDIFATSec != FREESECT, firstDIFATSec != ENDOFCHAIN {
            let perDIFAT = (sectorSize / 4) - 1
            var difSec = firstDIFATSec
            var guard0 = 0
            while difSec != ENDOFCHAIN, difSec != FREESECT {
                guard0 += 1; if guard0 > 10_000 { break }
                let off = 512 + Int(difSec) * sectorSize
                guard off + sectorSize <= data.count else { break }
                for i in 0..<perDIFAT {
                    let entry = readUInt32LE(in: data, offset: off + i * 4)
                    if entry == FREESECT || entry == ENDOFCHAIN { break }
                    fatSectorList.append(entry)
                }
                difSec = readUInt32LE(in: data, offset: off + perDIFAT * 4)
            }
        }

        // --- Build FAT ---
        let entriesPerSector = sectorSize / 4
        var fat: [UInt32] = []
        fat.reserveCapacity(fatSectorList.count * entriesPerSector)
        for sec in fatSectorList {
            let off = 512 + Int(sec) * sectorSize
            guard off + sectorSize <= data.count else { throw ProtectedXLSXReaderError.invalidFormat }
            for i in 0..<entriesPerSector {
                fat.append(readUInt32LE(in: data, offset: off + i * 4))
            }
        }
        guard !fat.isEmpty else { throw ProtectedXLSXReaderError.invalidFormat }

        // --- Follow a FAT chain, return concatenated sector bytes ---
        func readSectorChain(start: UInt32) -> Data {
            var result = Data()
            var sec = start
            var guard1 = 0
            while sec != ENDOFCHAIN, sec != FREESECT, Int(sec) < fat.count {
                guard1 += 1; if guard1 > 200_000 { break }
                let off = 512 + Int(sec) * sectorSize
                guard off + sectorSize <= data.count else { break }
                result.append(data[off ..< off + sectorSize])
                sec = fat[Int(sec)]
            }
            return result
        }

        // --- Read directory entries ---
        let dirRaw   = readSectorChain(start: UInt32(firstDirSector))
        let entryLen = 128
        guard dirRaw.count >= entryLen else { throw ProtectedXLSXReaderError.invalidFormat }

        struct CFBEntry {
            let name:  String
            let type:  UInt8
            let start: UInt32
            let size:  Int
        }

        var entries: [CFBEntry] = []
        var idx = 0
        while idx + entryLen <= dirRaw.count {
            let base    = idx
            let nameLen = Int(readUInt16LE(in: dirRaw, offset: base + 64))
            let type    = dirRaw[base + 66]
            let start   = readUInt32LE(in: dirRaw, offset: base + 116)
            let size    = Int(readUInt32LE(in: dirRaw, offset: base + 120))
            let name: String
            if nameLen >= 2, nameLen <= 64 {
                let nameBytes = dirRaw.subdata(in: base ..< (base + nameLen - 2))
                name = String(data: nameBytes, encoding: .utf16LittleEndian) ?? ""
            } else {
                name = ""
            }
            entries.append(CFBEntry(name: name, type: type, start: start, size: size))
            idx += entryLen
        }

        // Entry 0 is always the root storage (type == 5)
        guard let root = entries.first, root.type == 5 else {
            throw ProtectedXLSXReaderError.invalidFormat
        }

        // If neither stream is present this is a plain XLS, not encrypted OOXML
        guard
            let eiEntry = entries.first(where: { $0.name == "EncryptionInfo" }),
            let epEntry = entries.first(where: { $0.name == "EncryptedPackage" })
        else {
            throw ProtectedXLSXReaderError.notEncrypted
        }

        // --- Build mini FAT ---
        var miniFAT: [UInt32] = []
        if firstMiniFATSec != FREESECT, firstMiniFATSec != ENDOFCHAIN {
            var mSec = firstMiniFATSec
            var guard2 = 0
            while mSec != ENDOFCHAIN, mSec != FREESECT, Int(mSec) < fat.count {
                guard2 += 1; if guard2 > 10_000 { break }
                let off = 512 + Int(mSec) * sectorSize
                guard off + sectorSize <= data.count else { break }
                for j in 0..<entriesPerSector {
                    miniFAT.append(readUInt32LE(in: data, offset: off + j * 4))
                }
                mSec = fat[Int(mSec)]
            }
        }

        // Mini-stream container lives in the root's data sectors
        let miniContainer: Data = (root.start != ENDOFCHAIN && root.start != FREESECT)
            ? readSectorChain(start: root.start) : Data()

        // --- Read one stream (mini or regular) ---
        func readStream(_ entry: CFBEntry) -> Data {
            let useMini = entry.size < miniCutoff
                && !miniFAT.isEmpty
                && !miniContainer.isEmpty
            if useMini {
                var result = Data()
                var mSec = entry.start
                var guard3 = 0
                while mSec != ENDOFCHAIN, mSec != FREESECT, Int(mSec) < miniFAT.count {
                    guard3 += 1; if guard3 > 100_000 { break }
                    let off = Int(mSec) * miniSectorSize
                    guard off + miniSectorSize <= miniContainer.count else { break }
                    result.append(miniContainer[off ..< off + miniSectorSize])
                    mSec = miniFAT[Int(mSec)]
                }
                return Data(result.prefix(entry.size))
            } else {
                return Data(readSectorChain(start: entry.start).prefix(entry.size))
            }
        }

        let encryptionInfo   = readStream(eiEntry)
        let encryptedPackage = readStream(epEntry)

        guard !encryptionInfo.isEmpty, !encryptedPackage.isEmpty else {
            throw ProtectedXLSXReaderError.invalidFormat
        }

        return EncryptionPackage(encryptionInfo: encryptionInfo, encryptedPackage: encryptedPackage)
    }

    private static func parseAgileInfo(from data: Data) throws -> AgileInfo {
        guard data.count >= 8 else { throw ProtectedXLSXReaderError.invalidFormat }

        let major = readUInt16LE(in: data, offset: 0)
        let minor = readUInt16LE(in: data, offset: 2)
        guard major == 4, minor == 4 else {
            throw ProtectedXLSXReaderError.unsupportedEncryption
        }

        let xmlData = data.subdata(in: 8..<data.count)
        guard let xml = String(data: xmlData, encoding: .utf8) else {
            throw ProtectedXLSXReaderError.invalidFormat
        }

        guard
            let keyDataAttributes = attributes(forTag: "keyData", in: xml),
            let encryptedKeyAttributes = attributes(forTag: "encryptedKey", in: xml),
            let keyDataSalt = decodeBase64(keyDataAttributes["saltValue"]),
            let keyDataHashAlgorithm = keyDataAttributes["hashAlgorithm"],
            let encryptedKeyValue = decodeBase64(encryptedKeyAttributes["encryptedKeyValue"]),
            let encryptedKeySalt = decodeBase64(encryptedKeyAttributes["saltValue"]),
            let encryptedKeyHashAlgorithm = encryptedKeyAttributes["hashAlgorithm"],
            let spinCountString = encryptedKeyAttributes["spinCount"],
            let spinCount = UInt32(spinCountString),
            let keyBitsString = encryptedKeyAttributes["keyBits"],
            let keyBits = Int(keyBitsString)
        else {
            throw ProtectedXLSXReaderError.invalidFormat
        }

        return AgileInfo(
            keyData: AgileKeyData(
                saltValue: keyDataSalt,
                hashAlgorithm: keyDataHashAlgorithm
            ),
            encryptedKey: AgileEncryptedKey(
                spinCount: spinCount,
                encryptedKeyValue: encryptedKeyValue,
                saltValue: encryptedKeySalt,
                hashAlgorithm: encryptedKeyHashAlgorithm,
                keyBits: keyBits
            )
        )
    }

    // MARK: - Hash dispatcher (SHA1 / SHA256 / SHA512)
    //
    // Excel uses SHA1 for files saved by Office 2007-2016 and SHA512 for
    // Office 2016+ when "strong encryption" is chosen. Both are OOXML Agile.

    private static func agileHash(algorithm: String, data: Data) -> Data {
        if algorithm.caseInsensitiveCompare("SHA512") == .orderedSame {
            return Data(SHA512.hash(data: data))
        } else if algorithm.caseInsensitiveCompare("SHA256") == .orderedSame {
            return Data(SHA256.hash(data: data))
        } else {
            // SHA1 — used by Excel 2007-2016, keyBits=128, AES-128-CBC
            return Data(Insecure.SHA1.hash(data: data))
        }
    }

    private static func decryptPackage(_ data: Data, agileInfo: AgileInfo, password: String) throws -> Data {
        let keyAlg  = agileInfo.encryptedKey.hashAlgorithm
        let dataAlg = agileInfo.keyData.hashAlgorithm

        // Accept SHA1, SHA256, SHA512; reject anything else (e.g. MD5)
        let supported = ["SHA1", "SHA256", "SHA512"]
        guard supported.contains(where: { $0.caseInsensitiveCompare(keyAlg)  == .orderedSame }),
              supported.contains(where: { $0.caseInsensitiveCompare(dataAlg) == .orderedSame })
        else {
            throw ProtectedXLSXReaderError.unsupportedEncryption
        }

        guard let passwordData = password.data(using: .utf16LittleEndian) else {
            throw ProtectedXLSXReaderError.invalidPassword
        }

        let secretKey = try deriveSecretKey(passwordData: passwordData, encryptedKey: agileInfo.encryptedKey)

        guard data.count >= 8 else { throw ProtectedXLSXReaderError.invalidFormat }
        let totalSize = Int(readUInt32LE(in: data, offset: 0))
        let payload = data.subdata(in: 8..<data.count)

        let segmentLength = 4096
        let totalSegments = Int(ceil(Double(totalSize) / Double(segmentLength)))
        var result = Data()
        result.reserveCapacity(totalSize)

        var offset = 0
        for segmentIndex in 0..<totalSegments {
            let remainingBytes = payload.count - offset
            guard remainingBytes > 0 else { break }

            let encryptedChunkSize = min(segmentLength, remainingBytes)
            let encryptedChunk = payload.subdata(in: offset..<(offset + encryptedChunkSize))
            let ivSeed = agileInfo.keyData.saltValue + littleEndianData(UInt32(segmentIndex))
            // IV uses the keyData hash algorithm (may differ from encryptedKey algorithm)
            let iv = agileHash(algorithm: dataAlg, data: ivSeed).prefix(16)
            let decryptedChunk = try aesDecryptNoPadding(data: encryptedChunk, key: secretKey, iv: iv)

            let remainingOutput = totalSize - result.count
            let bytesToAppend = min(remainingOutput, decryptedChunk.count)
            result.append(decryptedChunk.prefix(bytesToAppend))
            offset += encryptedChunkSize
        }

        guard result.count == totalSize else {
            throw ProtectedXLSXReaderError.decryptionFailed
        }

        return result
    }

    private static func deriveSecretKey(passwordData: Data, encryptedKey: AgileEncryptedKey) throws -> Data {
        let alg = encryptedKey.hashAlgorithm
        let block3 = Data([0x14, 0x6E, 0x0B, 0xE7, 0xAB, 0xAC, 0xD0, 0xD6])
        var hash = agileHash(algorithm: alg, data: encryptedKey.saltValue + passwordData)

        for i in 0..<encryptedKey.spinCount {
            hash = agileHash(algorithm: alg, data: littleEndianData(i) + hash)
        }

        hash = agileHash(algorithm: alg, data: hash + block3)
        let decryptionKey = hash.prefix(encryptedKey.keyBits / 8)
        let decryptedVerifier = try aesDecryptNoPadding(
            data: encryptedKey.encryptedKeyValue,
            key: decryptionKey,
            iv: encryptedKey.saltValue
        )

        guard !decryptedVerifier.isEmpty else {
            throw ProtectedXLSXReaderError.invalidPassword
        }

        return decryptedVerifier
    }

    private static func aesDecryptNoPadding(data: Data, key: Data, iv: Data) throws -> Data {
        var outLength = 0
        var outData = Data(count: data.count + kCCBlockSizeAES128)
        let outputCapacity = outData.count

        let status = outData.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(0),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            outBytes.baseAddress, outputCapacity,
                            &outLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw ProtectedXLSXReaderError.invalidPassword
        }

        outData.removeSubrange(outLength..<outData.count)
        return outData
    }

    private static func attributes(forTag tag: String, in xml: String) -> [String: String]? {
        let pattern = "<(?:[A-Za-z0-9_]+:)?\(tag)\\b([^>]*)/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              let attributesRange = Range(match.range(at: 1), in: xml)
        else { return nil }

        let attributesString = String(xml[attributesRange])
        let attrPattern = #"([A-Za-z0-9_]+)="([^"]*)""#
        guard let attrRegex = try? NSRegularExpression(pattern: attrPattern, options: []) else { return nil }
        let attrRange = NSRange(attributesString.startIndex..<attributesString.endIndex, in: attributesString)
        let matches = attrRegex.matches(in: attributesString, options: [], range: attrRange)

        var result: [String: String] = [:]
        for match in matches {
            guard
                let keyRange = Range(match.range(at: 1), in: attributesString),
                let valueRange = Range(match.range(at: 2), in: attributesString)
            else { continue }
            result[String(attributesString[keyRange])] = String(attributesString[valueRange])
        }
        return result
    }

    private static func decodeBase64(_ value: String?) -> Data? {
        guard let value else { return nil }
        return Data(base64Encoded: value)
    }

    private static func readUInt16LE(in data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(in data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func littleEndianData(_ value: UInt32) -> Data {
        var le = value.littleEndian
        return Data(bytes: &le, count: MemoryLayout<UInt32>.size)
    }
}
