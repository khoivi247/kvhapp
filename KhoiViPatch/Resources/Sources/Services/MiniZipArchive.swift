import Foundation
import Compression

enum MiniZipError: LocalizedError {
    case invalidArchive
    case unsupportedCompression(UInt16)
    case decompressionFailed
    case crcMismatch(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "Tệp .kvh không phải định dạng nén hợp lệ."
        case .unsupportedCompression(let method):
            return "Phương thức nén ZIP không được hỗ trợ (method: \(method))."
        case .decompressionFailed:
            return "Giải nén dữ liệu trong tệp .kvh thất bại."
        case .crcMismatch(let name):
            return "Lỗi toàn vẹn dữ liệu CRC32 tại tệp: \(name)."
        }
    }
}

/// Pure-Swift ZIP reader & writer using Apple's built-in Compression framework (zero external dependencies).
enum MiniZipArchive {

    // MARK: - Read Archive

    static func readEntries(from archiveData: Data) throws -> [String: Data] {
        guard let eocdOffset = findEndOfCentralDirectory(in: archiveData) else {
            throw MiniZipError.invalidArchive
        }

        let totalEntries = Int(readUInt16(archiveData, at: eocdOffset + 10))
        let centralDirOffset = Int(readUInt32(archiveData, at: eocdOffset + 16))

        var cursor = centralDirOffset
        var result: [String: Data] = [:]

        for _ in 0..<totalEntries {
            guard cursor + 46 <= archiveData.count,
                  readUInt32(archiveData, at: cursor) == 0x02014B50 else {
                throw MiniZipError.invalidArchive
            }

            let method = readUInt16(archiveData, at: cursor + 10)
            let expectedCRC = readUInt32(archiveData, at: cursor + 16)
            let compressedSize = Int(readUInt32(archiveData, at: cursor + 20))
            let uncompressedSize = Int(readUInt32(archiveData, at: cursor + 24))
            let nameLen = Int(readUInt16(archiveData, at: cursor + 28))
            let extraLen = Int(readUInt16(archiveData, at: cursor + 30))
            let commentLen = Int(readUInt16(archiveData, at: cursor + 32))
            let localHeaderOffset = Int(readUInt32(archiveData, at: cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLen <= archiveData.count else { throw MiniZipError.invalidArchive }
            let nameData = archiveData.subdata(in: nameStart..<(nameStart + nameLen))
            let entryName = String(data: nameData, encoding: .utf8) ?? "entry_\(cursor)"

            cursor = nameStart + nameLen + extraLen + commentLen

            // Jump to Local File Header
            guard localHeaderOffset + 30 <= archiveData.count,
                  readUInt32(archiveData, at: localHeaderOffset) == 0x04034B50 else {
                throw MiniZipError.invalidArchive
            }

            let localNameLen = Int(readUInt16(archiveData, at: localHeaderOffset + 26))
            let localExtraLen = Int(readUInt16(archiveData, at: localHeaderOffset + 28))
            let payloadStart = localHeaderOffset + 30 + localNameLen + localExtraLen
            let payloadEnd = payloadStart + compressedSize

            guard payloadEnd <= archiveData.count else { throw MiniZipError.invalidArchive }
            let compressedPayload = archiveData.subdata(in: payloadStart..<payloadEnd)

            let outputData: Data
            if method == 0 {
                outputData = compressedPayload
            } else if method == 8 {
                outputData = try inflateRawDeflate(compressedPayload, expectedSize: max(uncompressedSize, 1))
            } else {
                throw MiniZipError.unsupportedCompression(method)
            }

            if !entryName.hasSuffix("/") {
                let actualCRC = crc32(outputData)
                if actualCRC != expectedCRC {
                    throw MiniZipError.crcMismatch(entryName)
                }
                result[entryName] = outputData
            }
        }

        return result
    }

    // MARK: - Write Archive

    static func writeArchive(entries: [String: Data]) -> Data {
        var fileSection = Data()
        var centralDirectory = Data()
        var entryCount: UInt16 = 0

        let sortedKeys = entries.keys.sorted()

        for name in sortedKeys {
            guard let rawData = entries[name],
                  let nameData = name.data(using: .utf8) else { continue }

            let crc = crc32(rawData)
            let compressed = deflateRaw(rawData)
            let useDeflate = compressed != nil && (compressed!.count < rawData.count)
            let method: UInt16 = useDeflate ? 8 : 0
            let payload = useDeflate ? compressed! : rawData

            let localOffset = UInt32(fileSection.count)

            // Local File Header (30 bytes)
            fileSection.appendUInt32(0x04034B50)
            fileSection.appendUInt16(20) // Version needed
            fileSection.appendUInt16(0x0800) // UTF-8 flag
            fileSection.appendUInt16(method)
            fileSection.appendUInt16(0) // mod time
            fileSection.appendUInt16(0x5421) // mod date
            fileSection.appendUInt32(crc)
            fileSection.appendUInt32(UInt32(payload.count))
            fileSection.appendUInt32(UInt32(rawData.count))
            fileSection.appendUInt16(UInt16(nameData.count))
            fileSection.appendUInt16(0) // extra len
            fileSection.append(nameData)
            fileSection.append(payload)

            // Central Directory Header (46 bytes)
            centralDirectory.appendUInt32(0x02014B50)
            centralDirectory.appendUInt16(0x031E) // made by Unix
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0x0800)
            centralDirectory.appendUInt16(method)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0x5421)
            centralDirectory.appendUInt32(crc)
            centralDirectory.appendUInt32(UInt32(payload.count))
            centralDirectory.appendUInt32(UInt32(rawData.count))
            centralDirectory.appendUInt16(UInt16(nameData.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(localOffset)
            centralDirectory.append(nameData)

            entryCount &+= 1
        }

        let centralDirOffset = UInt32(fileSection.count)
        let centralDirSize = UInt32(centralDirectory.count)

        var endRecord = Data()
        endRecord.appendUInt32(0x06054B50)
        endRecord.appendUInt16(0)
        endRecord.appendUInt16(0)
        endRecord.appendUInt16(entryCount)
        endRecord.appendUInt16(entryCount)
        endRecord.appendUInt32(centralDirSize)
        endRecord.appendUInt32(centralDirOffset)
        endRecord.appendUInt16(0)

        var archive = Data()
        archive.append(fileSection)
        archive.append(centralDirectory)
        archive.append(endRecord)
        return archive
    }

    // MARK: - Compression Helpers

    private static func deflateRaw(_ input: Data) -> Data? {
        guard !input.isEmpty else { return Data() }
        let destCapacity = max(input.count + 128, 1024)
        var destBuffer = [UInt8](repeating: 0, count: destCapacity)

        let writtenBytes = input.withUnsafeBytes { rawBuffer -> Int in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(
                &destBuffer,
                destCapacity,
                base,
                input.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard writtenBytes > 0 else { return nil }
        return Data(destBuffer.prefix(writtenBytes))
    }

    private static func inflateRawDeflate(_ input: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 || input.isEmpty { return Data() }
        var capacity = max(expectedSize, input.count * 4)

        for _ in 0..<4 {
            var destBuffer = [UInt8](repeating: 0, count: capacity)
            let decodedBytes = input.withUnsafeBytes { rawBuffer -> Int in
                guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    &destBuffer,
                    capacity,
                    base,
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
            if decodedBytes > 0 && (decodedBytes == expectedSize || decodedBytes < capacity) {
                return Data(destBuffer.prefix(decodedBytes))
            }
            capacity *= 2
        }
        throw MiniZipError.decompressionFailed
    }

    // MARK: - Low-level Binary & CRC32

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let minOffset = max(0, data.count - 65557)
        for i in stride(from: data.count - 22, through: minOffset, by: -1) {
            if readUInt32(data, at: i) == 0x06054B50 {
                return i
            }
        }
        return nil
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
