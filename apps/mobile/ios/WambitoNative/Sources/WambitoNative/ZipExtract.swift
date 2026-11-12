import Compression
import Foundation

public enum ZipError: Error, Equatable {
  case notZip
  case unsupported(String)
  case outside(String)
  case truncated
}

/// Unzips a downloaded voice model. iOS has no unzip API, so this reads the central directory and
/// streams each entry through Apple's Compression framework. Mirrors the Android `ZipExtract.kt`:
/// an entry that would land outside the target is refused (zip slip).
public enum ZipExtract {
  private static let chunk = 64 * 1024

  private struct Entry {
    let name: String
    let method: UInt16
    let compressedSize: UInt64
    let size: UInt64
    let localOffset: UInt64
    let target: URL
    let isDirectory: Bool
  }

  /// Unzips `zip` into `into`. On any error everything this call created under `into` is removed.
  public static func unzip(_ zip: URL, into: URL) throws {
    let handle = try FileHandle(forReadingFrom: zip)
    defer { try? handle.close() }

    let fm = FileManager.default
    var created: [URL] = []
    do {
      let fileSize = try handle.seekToEnd()
      let entries = try readDirectory(handle, fileSize: fileSize, into: into)

      if !fm.fileExists(atPath: into.path) {
        try fm.createDirectory(at: into, withIntermediateDirectories: true)
        created.append(into)
      }
      for entry in entries {
        if entry.isDirectory {
          try makeDirectories(entry.target, fm: fm, created: &created)
        } else {
          try makeDirectories(entry.target.deletingLastPathComponent(), fm: fm, created: &created)
          try extract(entry, from: handle, fileSize: fileSize, fm: fm, created: &created)
        }
      }
    } catch {
      for url in created.reversed() { try? fm.removeItem(at: url) }
      throw error
    }
  }

  // MARK: Central directory

  private static func u16(_ d: Data, _ o: Int) -> UInt16 {
    UInt16(d[d.startIndex + o]) | UInt16(d[d.startIndex + o + 1]) << 8
  }

  private static func u32(_ d: Data, _ o: Int) -> UInt32 {
    UInt32(u16(d, o)) | UInt32(u16(d, o + 2)) << 16
  }

  private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
    try handle.seek(toOffset: offset)
    guard let data = try handle.read(upToCount: count), data.count == count else {
      throw ZipError.truncated
    }
    return data
  }

  private static func readDirectory(_ handle: FileHandle, fileSize: UInt64, into: URL) throws
    -> [Entry]
  {
    guard fileSize >= 22 else { throw ZipError.notZip }
    let tailSize = Int(min(fileSize, 22 + 65535))
    let tail = try read(handle, at: fileSize - UInt64(tailSize), count: tailSize)
    var eocd = -1
    var i = tailSize - 22
    while i >= 0 {
      if u32(tail, i) == 0x0605_4b50 {
        eocd = i
        break
      }
      i -= 1
    }
    guard eocd >= 0 else { throw ZipError.notZip }

    let count = u16(tail, eocd + 10)
    let dirSize = u32(tail, eocd + 12)
    let dirOffset = u32(tail, eocd + 16)
    if count == 0xFFFF || dirSize == 0xFFFF_FFFF || dirOffset == 0xFFFF_FFFF {
      throw ZipError.unsupported("zip64")
    }
    guard UInt64(dirOffset) + UInt64(dirSize) <= fileSize else { throw ZipError.truncated }
    let dir = try read(handle, at: UInt64(dirOffset), count: Int(dirSize))

    let root = into.standardizedFileURL.resolvingSymlinksInPath()
    var entries: [Entry] = []
    var pos = 0
    for _ in 0..<Int(count) {
      guard pos + 46 <= dir.count, u32(dir, pos) == 0x0201_4b50 else { throw ZipError.truncated }
      let flags = u16(dir, pos + 8)
      let method = u16(dir, pos + 10)
      let compressed = u32(dir, pos + 20)
      let size = u32(dir, pos + 24)
      let nameLen = Int(u16(dir, pos + 28))
      let extraLen = Int(u16(dir, pos + 30))
      let commentLen = Int(u16(dir, pos + 32))
      let offset = u32(dir, pos + 42)
      guard pos + 46 + nameLen + extraLen + commentLen <= dir.count else {
        throw ZipError.truncated
      }
      let nameBytes = dir.subdata(in: (dir.startIndex + pos + 46)..<(dir.startIndex + pos + 46 + nameLen))
      let name = String(decoding: nameBytes, as: UTF8.self)
      pos += 46 + nameLen + extraLen + commentLen

      let target = try resolve(name, in: root)
      let isDirectory = name.hasSuffix("/")
      if flags & 0x1 != 0 || flags & 0x40 != 0 { throw ZipError.unsupported("encrypted") }
      if !isDirectory {
        if compressed == 0xFFFF_FFFF || size == 0xFFFF_FFFF || offset == 0xFFFF_FFFF {
          throw ZipError.unsupported("zip64")
        }
        if method != 0 && method != 8 { throw ZipError.unsupported("method \(method)") }
      }
      entries.append(
        Entry(
          name: name, method: method, compressedSize: UInt64(compressed), size: UInt64(size),
          localOffset: UInt64(offset), target: target, isDirectory: isDirectory))
    }
    return entries
  }

  /// The place `name` extracts to, or `.outside(name)` when it would leave `root`.
  private static func resolve(_ name: String, in root: URL) throws -> URL {
    let slashed = name.replacingOccurrences(of: "\\", with: "/")
    let parts = slashed.split(separator: "/", omittingEmptySubsequences: false)
    if name.isEmpty || name.contains("\0") || slashed.hasPrefix("/") || parts.contains("..") {
      throw ZipError.outside(name)
    }
    let target = root.appendingPathComponent(slashed).standardizedFileURL
    guard target.path.hasPrefix(root.path + "/") else { throw ZipError.outside(name) }
    return target
  }

  // MARK: Writing

  private static func makeDirectories(_ dir: URL, fm: FileManager, created: inout [URL]) throws {
    var missing: [URL] = []
    var current = dir
    while !fm.fileExists(atPath: current.path) {
      missing.append(current)
      let parent = current.deletingLastPathComponent()
      if parent.path == current.path { break }
      current = parent
    }
    for url in missing.reversed() {
      try fm.createDirectory(at: url, withIntermediateDirectories: false)
      created.append(url)
    }
  }

  private static func extract(
    _ entry: Entry, from handle: FileHandle, fileSize: UInt64, fm: FileManager,
    created: inout [URL]
  ) throws {
    let local = try read(handle, at: entry.localOffset, count: 30)
    guard u32(local, 0) == 0x0403_4b50 else { throw ZipError.truncated }
    let start = entry.localOffset + 30 + UInt64(u16(local, 26)) + UInt64(u16(local, 28))
    guard start + entry.compressedSize <= fileSize else { throw ZipError.truncated }

    if !fm.fileExists(atPath: entry.target.path) { created.append(entry.target) }
    guard fm.createFile(atPath: entry.target.path, contents: nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    let out = try FileHandle(forWritingTo: entry.target)
    defer { try? out.close() }

    try handle.seek(toOffset: start)
    var written: UInt64 = 0
    if entry.method == 0 {
      guard entry.compressedSize == entry.size else { throw ZipError.truncated }
      var left = entry.compressedSize
      while left > 0 {
        let want = Int(min(UInt64(chunk), left))
        guard let data = try handle.read(upToCount: want), data.count == want else {
          throw ZipError.truncated
        }
        try out.write(contentsOf: data)
        written += UInt64(want)
        left -= UInt64(want)
      }
    } else {
      written = try inflate(from: handle, compressedSize: entry.compressedSize, to: out)
    }
    guard written == entry.size else { throw ZipError.truncated }
  }

  /// Raw deflate (`COMPRESSION_ZLIB`) streamed in 64 KiB chunks. Returns the bytes written.
  private static func inflate(from handle: FileHandle, compressedSize: UInt64, to out: FileHandle)
    throws -> UInt64
  {
    let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
    let src = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
    defer {
      dst.deallocate()
      src.deallocate()
    }
    var stream = compression_stream(
      dst_ptr: dst, dst_size: 0, src_ptr: UnsafePointer(src), src_size: 0, state: nil)
    guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
      == COMPRESSION_STATUS_OK
    else { throw ZipError.unsupported("inflate") }
    defer { compression_stream_destroy(&stream) }

    var remaining = compressedSize
    var written: UInt64 = 0
    stream.dst_ptr = dst
    stream.dst_size = chunk
    while true {
      if stream.src_size == 0 && remaining > 0 {
        let want = Int(min(UInt64(chunk), remaining))
        guard let data = try handle.read(upToCount: want), data.count == want else {
          throw ZipError.truncated
        }
        data.copyBytes(to: src, count: want)
        stream.src_ptr = UnsafePointer(src)
        stream.src_size = want
        remaining -= UInt64(want)
      }
      let flags = (remaining == 0 && stream.src_size == 0) ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
      let status = compression_stream_process(&stream, flags)
      let produced = chunk - stream.dst_size
      if produced > 0 {
        try out.write(contentsOf: Data(bytes: dst, count: produced))
        written += UInt64(produced)
        stream.dst_ptr = dst
        stream.dst_size = chunk
      }
      switch status {
      case COMPRESSION_STATUS_END:
        return written
      case COMPRESSION_STATUS_OK:
        if remaining == 0 && stream.src_size == 0 && produced == 0 && flags != 0 {
          throw ZipError.truncated
        }
      default:
        throw ZipError.truncated
      }
    }
  }
}
