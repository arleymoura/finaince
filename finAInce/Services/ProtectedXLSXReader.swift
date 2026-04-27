import CommonCrypto
import CryptoKit
import Foundation

@_silgen_name("ProtectedXLSXCopyStreamsJSON")
private func ProtectedXLSXCopyStreamsJSON(
    _ bytes: UnsafePointer<UInt8>,
    _ length: Int32,
    _ errorCode: UnsafeMutablePointer<Int32>
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("ProtectedXLSXFreeCString")
private func ProtectedXLSXFreeCString(_ pointer: UnsafeMutablePointer<CChar>?)

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
        let streams = try extractStreams(from: data)
        let agileInfo = try parseAgileInfo(from: streams.encryptionInfo)
        let decryptedData = try decryptPackage(streams.encryptedPackage, agileInfo: agileInfo, password: password)
        return try XLSXReader.rows(from: decryptedData)
    }

    private static func extractStreams(from data: Data) throws -> EncryptionPackage {
        var errorCode: Int32 = 0
        let jsonPointer: UnsafeMutablePointer<CChar>? = data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            return ProtectedXLSXCopyStreamsJSON(baseAddress, Int32(data.count), &errorCode)
        }

        guard let jsonPointer else {
            switch errorCode {
            case 2:
                throw ProtectedXLSXReaderError.notEncrypted
            default:
                throw ProtectedXLSXReaderError.invalidFormat
            }
        }

        defer { ProtectedXLSXFreeCString(jsonPointer) }

        let jsonData = Data(bytes: jsonPointer, count: strlen(jsonPointer))
        guard
            let object = try JSONSerialization.jsonObject(with: jsonData) as? [String: String],
            let encryptionInfoBase64 = object["encryptionInfo"],
            let encryptedPackageBase64 = object["encryptedPackage"],
            let encryptionInfo = Data(base64Encoded: encryptionInfoBase64),
            let encryptedPackage = Data(base64Encoded: encryptedPackageBase64)
        else {
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

    private static func decryptPackage(_ data: Data, agileInfo: AgileInfo, password: String) throws -> Data {
        guard agileInfo.encryptedKey.hashAlgorithm.caseInsensitiveCompare("SHA512") == .orderedSame,
              agileInfo.keyData.hashAlgorithm.caseInsensitiveCompare("SHA512") == .orderedSame else {
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
            let iv = Data(SHA512.hash(data: ivSeed)).prefix(16)
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
        let block3 = Data([0x14, 0x6E, 0x0B, 0xE7, 0xAB, 0xAC, 0xD0, 0xD6])
        var hash = Data(SHA512.hash(data: encryptedKey.saltValue + passwordData))

        for i in 0..<encryptedKey.spinCount {
            hash = Data(SHA512.hash(data: littleEndianData(i) + hash))
        }

        hash = Data(SHA512.hash(data: hash + block3))
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
                            outBytes.baseAddress, outData.count,
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
