import Darwin
import Foundation
import XCTest
@testable import RacketCore

final class BulkDirectoryReaderTests: XCTestCase {
    func testSuccessfulRecordCanOmitRequestedErrorAttribute() throws {
        let result = try decode(record(name: "cache.bin", flags: 0))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "cache.bin")
        XCTAssertEqual(result[0].flags, 0)
        XCTAssertEqual(result[0].error, 0)
    }

    func testErrorPrecedesNameAndMissingFlagsRemainAbsent() throws {
        let result = try decode(record(name: "denied", flags: nil, error: EACCES))
        XCTAssertEqual(result[0].name, "denied")
        XCTAssertEqual(result[0].error, EACCES)
        XCTAssertNil(result[0].flags)
    }

    func testDatalessFlagSurvivesWithoutRequestingAnySizeField() throws {
        let result = try decode(record(name: "offline", flags: UInt32(SF_DATALESS)))
        XCTAssertEqual(result[0].flags, UInt32(SF_DATALESS))
        XCTAssertEqual(BulkDirectoryReader.requested, UInt32(ATTR_CMN_RETURNED_ATTRS) | UInt32(ATTR_CMN_NAME) | UInt32(ATTR_CMN_FLAGS) | UInt32(ATTR_CMN_ERROR))
    }

    func testMultipleVariableRecordsAndUnicodeNamesDecode() throws {
        let bytes = record(name: "a", flags: 0) + record(name: "çekim 🎬", flags: 0)
        let result = try decode(bytes, count: 2)
        XCTAssertEqual(result.map(\.name), ["a", "çekim 🎬"])
    }

    func testInvalidLengthsAndTruncatedRecordsFailClosed() {
        let original = record(name: "cache", flags: 0)
        for length: UInt32 in [0, 4, 25, UInt32.max] {
            var bytes = original
            replace(&bytes, at: 0, with: length)
            XCTAssertThrowsError(try decode(bytes))
        }
        XCTAssertThrowsError(try decode(Data(original.dropLast())))
        XCTAssertThrowsError(try decode(original, count: 2))
        XCTAssertThrowsError(try decode(original, count: -1))
    }

    func testNameReferencesCannotLeaveTheirRecord() {
        for offset: Int32 in [-100, 0, 4, Int32.max] {
            var bytes = record(name: "cache", flags: 0)
            replace(&bytes, at: 24, with: offset)
            XCTAssertThrowsError(try decode(bytes))
        }
        var bytes = record(name: "cache", flags: 0)
        replace(&bytes, at: 28, with: UInt32.max)
        XCTAssertThrowsError(try decode(bytes))
    }

    func testPathComponentsAndMalformedStringsAreRefused() {
        for name in ["", ".", "..", "a/b", "a\0b", "a\nb", String(repeating: "x", count: 256)] {
            XCTAssertThrowsError(try decode(record(name: name, flags: 0)))
        }
        var unterminated = record(name: "cache", flags: 0)
        unterminated[36 + "cache".utf8.count] = 1
        XCTAssertThrowsError(try decode(unterminated))
        var invalidUTF8 = record(name: "cache", flags: 0)
        invalidUTF8[36] = 0xFF
        XCTAssertThrowsError(try decode(invalidUTF8))
    }

    func testUnexpectedOrMissingAttributeMasksAreRefused() {
        for mask in [UInt32(ATTR_CMN_NAME), BulkDirectoryReader.requested | UInt32(ATTR_CMN_OBJTYPE)] {
            var bytes = record(name: "cache", flags: 0)
            replace(&bytes, at: 4, with: mask)
            XCTAssertThrowsError(try decode(bytes))
        }
        var bytes = record(name: "cache", flags: 0)
        replace(&bytes, at: 16, with: UInt32(ATTR_FILE_ALLOCSIZE))
        XCTAssertThrowsError(try decode(bytes))
    }

    private func decode(_ data: Data, count: Int = 1) throws -> [BulkDirectoryEntry] {
        try data.withUnsafeBytes { try BulkDirectoryReader.decode($0, count: count) }
    }

    private func record(name: String, flags: UInt32?, error: Int32? = nil) -> Data {
        var data = Data()
        append(UInt32(0), to: &data)
        var mask = UInt32(ATTR_CMN_RETURNED_ATTRS) | UInt32(ATTR_CMN_NAME)
        if flags != nil { mask |= UInt32(ATTR_CMN_FLAGS) }
        if error != nil { mask |= UInt32(ATTR_CMN_ERROR) }
        append(mask, to: &data)
        for _ in 0..<4 { append(UInt32(0), to: &data) }
        if let error { append(error, to: &data) }
        append(Int32(flags == nil ? 8 : 12), to: &data)
        append(UInt32(name.utf8.count + 1), to: &data)
        if let flags { append(flags, to: &data) }
        data.append(contentsOf: name.utf8)
        data.append(0)
        while data.count % 8 != 0 { data.append(0) }
        replace(&data, at: 0, with: UInt32(data.count))
        return data
    }

    private func append<T>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
    }

    private func replace<T>(_ data: inout Data, at offset: Int, with value: T) {
        withUnsafeBytes(of: value) { bytes in
            data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }
    }
}
