import XCTest
@testable import WambitoNative

final class ZipExtractTests: XCTestCase {
  private var root: URL!
  private let fm = FileManager.default

  override func setUpWithError() throws {
    try super.setUpWithError()
    guard fm.isExecutableFile(atPath: "/usr/bin/zip") else {
      throw XCTSkip("/usr/bin/zip is missing")
    }
    root = fm.temporaryDirectory.appendingPathComponent("zip-extract-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDown() {
    if let root { try? fm.removeItem(at: root) }
    super.tearDown()
  }

  private func zip(_ args: [String], cwd: URL, output: String = "x.zip") throws -> URL {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = cwd
    let out = root.appendingPathComponent(output)
    process.arguments = ["-q"] + [out.path] + args
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return out
  }

  private func makeInto() throws -> URL {
    let into = root.appendingPathComponent("into")
    try fm.createDirectory(at: into, withIntermediateDirectories: true)
    return into
  }

  private func randomData(_ count: Int) -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
  }

  private func files(in url: URL) -> [String] {
    let items = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
    return (items?.allObjects as? [URL] ?? []).filter {
      (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }.map(\.path)
  }

  func testStoredAndDeflated() throws {
    let src = root.appendingPathComponent("src")
    try fm.createDirectory(at: src.appendingPathComponent("dir"), withIntermediateDirectories: true)
    let a = Data("hello stored".utf8)
    let b = randomData(200 * 1024) + Data(repeating: 7, count: 100 * 1024)
    try a.write(to: src.appendingPathComponent("a.txt"))
    try b.write(to: src.appendingPathComponent("dir/b.bin"))
    _ = try zip(["-0", "a.txt"], cwd: src)
    let archive = try zip(["-9", "dir/b.bin"], cwd: src)
    let into = try makeInto()

    try ZipExtract.unzip(archive, into: into)

    XCTAssertEqual(try Data(contentsOf: into.appendingPathComponent("a.txt")), a)
    XCTAssertEqual(try Data(contentsOf: into.appendingPathComponent("dir/b.bin")), b)
  }

  func testZipSlipRefused() throws {
    let sub = root.appendingPathComponent("sub")
    try fm.createDirectory(at: sub, withIntermediateDirectories: true)
    try Data("evil".utf8).write(to: root.appendingPathComponent("evil.txt"))
    let archive = try zip(["../evil.txt"], cwd: sub, output: "slip.zip")
    let into = try makeInto()
    let before = Set(try fm.contentsOfDirectory(atPath: root.path))

    XCTAssertThrowsError(try ZipExtract.unzip(archive, into: into)) {
      XCTAssertEqual($0 as? ZipError, .outside("../evil.txt"))
    }

    XCTAssertEqual(try fm.contentsOfDirectory(atPath: into.path), [])
    XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: root.path)), before)
  }

  func testTruncatedFails() throws {
    let src = root.appendingPathComponent("src")
    try fm.createDirectory(at: src, withIntermediateDirectories: true)
    try randomData(200 * 1024).write(to: src.appendingPathComponent("b.bin"))
    let archive = try zip(["-9", "b.bin"], cwd: src)
    let full = try Data(contentsOf: archive)
    try full.prefix(full.count / 2).write(to: archive)
    let into = try makeInto()

    XCTAssertThrowsError(try ZipExtract.unzip(archive, into: into))
    XCTAssertEqual(files(in: into), [])
  }

  func testNotAZip() throws {
    let file = root.appendingPathComponent("t.zip")
    try Data("this is not a zip file at all, just text".utf8).write(to: file)
    let into = try makeInto()

    XCTAssertThrowsError(try ZipExtract.unzip(file, into: into)) {
      XCTAssertEqual($0 as? ZipError, .notZip)
    }
  }

  func testEncryptedRefused() throws {
    let src = root.appendingPathComponent("src")
    try fm.createDirectory(at: src, withIntermediateDirectories: true)
    try Data("secret data".utf8).write(to: src.appendingPathComponent("s.txt"))
    let archive = try zip(["-P", "secret", "s.txt"], cwd: src)
    let into = try makeInto()

    XCTAssertThrowsError(try ZipExtract.unzip(archive, into: into)) {
      guard case .unsupported = $0 as? ZipError else {
        return XCTFail("expected unsupported, got \($0)")
      }
    }
    XCTAssertEqual(files(in: into), [])
  }

  func testPartialWriteIsCleanedUp() throws {
    let src = root.appendingPathComponent("src")
    try fm.createDirectory(at: src, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 4096).write(to: src.appendingPathComponent("first.bin"))
    // Small alphabet: compressible, so zip really deflates it (pure random would be stored).
    try Data(randomData(200 * 1024).map { $0 % 16 }).write(to: src.appendingPathComponent("second.bin"))
    let archive = try zip(["-9", "first.bin", "second.bin"], cwd: src)
    var bytes = try Data(contentsOf: archive)
    // Flip bytes in the middle of the second entry's data (second.bin is stored last, after first).
    let mid = bytes.count - 20 * 1024
    for i in mid..<(mid + 64) { bytes[i] ^= 0xFF }
    try bytes.write(to: archive)
    let into = try makeInto()

    XCTAssertThrowsError(try ZipExtract.unzip(archive, into: into))
    XCTAssertEqual(try fm.contentsOfDirectory(atPath: into.path), [])
  }

  private func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size_max) : 0
  }

  func testLargeStoredEntryDoesNotAccumulateMemory() throws {
    let src = root.appendingPathComponent("src")
    try fm.createDirectory(at: src, withIntermediateDirectories: true)
    let big = src.appendingPathComponent("big.bin")
    fm.createFile(atPath: big.path, contents: nil)
    let h = try FileHandle(forWritingTo: big)
    let block = randomData(1024 * 1024)
    for _ in 0..<150 { try h.write(contentsOf: block) }
    try h.close()
    let archive = try zip(["-0", "big.bin"], cwd: src)
    let into = try makeInto()

    let before = residentBytes()
    try ZipExtract.unzip(archive, into: into)
    let after = residentBytes()

    let size = try fm.attributesOfItem(atPath: into.appendingPathComponent("big.bin").path)[.size] as? UInt64
    XCTAssertEqual(size, 150 * 1024 * 1024)
    // Peak resident growth must stay far below the 150 MiB entry.
    XCTAssertLessThan(after > before ? after - before : 0, 60 * 1024 * 1024)
  }
}
