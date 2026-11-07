import XCTest
@testable import Marmot

/// The duplicate scan samples large files; removal re-checks the full bytes.
final class DuplicateVerificationTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("marmot-dup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ name: String, _ data: Data) throws -> String {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url.path
    }

    func testIdenticalFilesMatch() throws {
        let bytes = Data((0..<3_000_000).map { UInt8($0 % 251) })
        let first = try write("a.bin", bytes)
        let second = try write("b.bin", bytes)
        XCTAssertTrue(DuplicateEngine.filesAreIdentical(first, second))
    }

    /// Same size, same head/middle/tail samples, different in between: the
    /// sampled scan hash can't tell these apart, the full check must.
    func testSampledLookalikesAreRejected() throws {
        let size = 6 * 1024 * 1024
        let original = Data(repeating: 0, count: size)
        var changed = original
        changed[1_500_000] = 1   // between the head and middle samples
        let first = try write("a.img", original)
        let second = try write("b.img", changed)

        XCTAssertEqual(DuplicateEngine.contentKey(path: first, size: Int64(size)),
                       DuplicateEngine.contentKey(path: second, size: Int64(size)))
        XCTAssertFalse(DuplicateEngine.filesAreIdentical(first, second))
    }

    func testMissingOrSameFileNeverMatches() throws {
        let first = try write("a.bin", Data([1, 2, 3]))
        XCTAssertFalse(DuplicateEngine.filesAreIdentical(first, first))
        XCTAssertFalse(DuplicateEngine.filesAreIdentical(first, directory.appendingPathComponent("gone").path))
    }
}
