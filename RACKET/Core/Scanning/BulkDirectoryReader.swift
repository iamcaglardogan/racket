import Darwin
import Foundation

struct BulkDirectoryEntry: Sendable {
    let name: String
    let flags: UInt32?
    let error: Int32
}

/// Requests names and flags only. No stat, logical size, or allocation field is
/// requested for the batch: dataless entries are gated before further access.
enum BulkDirectoryReader {
    static let requested = UInt32(ATTR_CMN_RETURNED_ATTRS) | UInt32(ATTR_CMN_NAME) | UInt32(ATTR_CMN_ERROR) | UInt32(ATTR_CMN_FLAGS)

    static func next(descriptor: Int32) throws -> [BulkDirectoryEntry] {
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = requested
        // UInt64 storage supplies the alignment required by getattrlistbulk.
        var storage = [UInt64](repeating: 0, count: 8_192)
        return try storage.withUnsafeMutableBytes { bytes in
            let count = Darwin.getattrlistbulk(descriptor, &attributes, bytes.baseAddress!, bytes.count, UInt64(FSOPT_NOFOLLOW))
            guard count >= 0 else { throw scanSystemError(errno) }
            return try decode(UnsafeRawBufferPointer(bytes), count: Int(count))
        }
    }

    /// Darwin packs variable records, including unaligned fields. A malformed
    /// batch fails closed rather than letting a name reference escape its record.
    static func decode(_ buffer: UnsafeRawBufferPointer, count: Int) throws -> [BulkDirectoryEntry] {
        guard count >= 0, count <= buffer.count / 24 else { throw ScanMetadataError.unsupportedMetadata }
        var entries: [BulkDirectoryEntry] = []
        var offset = 0
        for _ in 0..<count {
            guard offset <= buffer.count - 4 else { throw ScanMetadataError.unsupportedMetadata }
            let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            guard length >= 24, length % 8 == 0, length <= buffer.count - offset else {
                throw ScanMetadataError.unsupportedMetadata
            }
            let end = offset + length
            var cursor = offset + 4
            func read<T>(_ type: T.Type) throws -> T {
                guard MemoryLayout<T>.size <= end - cursor else { throw ScanMetadataError.unsupportedMetadata }
                let value = buffer.loadUnaligned(fromByteOffset: cursor, as: type)
                cursor += MemoryLayout<T>.size
                return value
            }
            let returned = try read(attribute_set_t.self)
            guard returned.commonattr & ~requested == 0,
                  returned.commonattr & (UInt32(ATTR_CMN_RETURNED_ATTRS) | UInt32(ATTR_CMN_NAME)) == (UInt32(ATTR_CMN_RETURNED_ATTRS) | UInt32(ATTR_CMN_NAME)),
                  returned.volattr == 0, returned.dirattr == 0, returned.fileattr == 0, returned.forkattr == 0 else {
                throw ScanMetadataError.unsupportedMetadata
            }
            // RETURNED_ATTRS is first; ERROR, when present, precedes NAME.
            let error = returned.commonattr & UInt32(ATTR_CMN_ERROR) != 0 ? try read(Int32.self) : 0
            let referenceOffset = cursor
            let reference = try read(attrreference_t.self)
            let flags = returned.commonattr & UInt32(ATTR_CMN_FLAGS) != 0 ? try read(UInt32.self) : nil
            let nameStart = referenceOffset + Int(reference.attr_dataoffset)
            let nameLength = Int(reference.attr_length)
            guard nameLength > 1, nameLength <= 256, nameStart >= cursor,
                  nameStart <= end, nameLength <= end - nameStart else {
                throw ScanMetadataError.unsupportedMetadata
            }
            let nameBytes = buffer[nameStart..<(nameStart + nameLength)]
            guard nameBytes.last == 0, !nameBytes.dropLast().contains(0),
                  let name = String(bytes: nameBytes.dropLast(), encoding: .utf8),
                  name != ".", name != "..", !name.contains("/"),
                  !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw ScanMetadataError.unsupportedMetadata
            }
            entries.append(BulkDirectoryEntry(name: name, flags: flags, error: error))
            offset = end
        }
        return entries
    }
}

func scanSystemError(_ code: Int32) -> any Error {
    switch code {
    case EDEADLK: ScanMetadataError.dataless
    case ELOOP: PathGuardError.symbolicLink
    case ENOENT: PathGuardError.missing
    case ENOTDIR: PathGuardError.notDirectory
    case ENAMETOOLONG, EINVAL: PathGuardError.invalidPath
    default: ScanMetadataError.system(code)
    }
}
