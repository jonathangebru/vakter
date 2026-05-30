// Tar.swift
//
// Minimal gzipped-tar writer. We don't link Compression.framework on
// Linux, and we don't want to shell out to `tar` because the publisher
// is supposed to be reproducible from the same Swift binary on both
// macOS and Ubuntu CI runners. So this file builds the ustar archive
// and gzips it via `Process { tar/gzip }` on macOS, where /usr/bin/tar
// is always present (and the GitHub Actions macOS runner has gzip too).
//
// Implementation note: building an in-memory ustar is short. We do that
// here for the archive itself. For gzip we shell out to `/usr/bin/gzip`
// — Foundation has no built-in gzip and reimplementing DEFLATE is way
// out of scope. The CI workflow runs on macos-latest where gzip is
// guaranteed; if we ever move to a Linux runner we'll switch to
// swift-corelibs-foundation's URLSession-based zlib bridge or vend a
// Swift gzip pod.

import Foundation

enum TarError: Error, CustomStringConvertible {
    case fileNameTooLong(String)
    case gzipFailed(String)

    var description: String {
        switch self {
        case .fileNameTooLong(let n): return "tar entry name > 100 bytes: \(n)"
        case .gzipFailed(let s): return "gzip pipe failed: \(s)"
        }
    }
}

/// Take a directory whose immediate children are the bundle files and
/// produce a gzipped tar archive of those files (no parent directory
/// component, since the spec says the inside of the tarball is flat).
func makeTar(bundleDir: URL) throws -> Data {
    let fm = FileManager.default
    let entries = try fm.contentsOfDirectory(at: bundleDir, includingPropertiesForKeys: nil)
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var tar = Data()
    for entry in entries {
        guard fm.fileExists(atPath: entry.path) else { continue }
        let name = entry.lastPathComponent
        let data = try Data(contentsOf: entry)
        try writeTarEntry(name: name, data: data, into: &tar)
    }
    // tar trailer: two empty 512-byte blocks
    tar.append(Data(count: 1024))
    return try gzip(tar)
}

private func writeTarEntry(name: String, data: Data, into tar: inout Data) throws {
    guard name.utf8.count <= 100 else { throw TarError.fileNameTooLong(name) }
    var header = Data(count: 512)
    // name: 0..100
    let nameBytes = Array(name.utf8)
    for (i, b) in nameBytes.enumerated() { header[i] = b }
    // mode: 100..108 — "0000644 "
    setOctal(in: &header, range: 100..<108, value: 0o644, width: 7)
    // uid/gid: 108..116, 116..124
    setOctal(in: &header, range: 108..<116, value: 0, width: 7)
    setOctal(in: &header, range: 116..<124, value: 0, width: 7)
    // size: 124..136
    setOctal(in: &header, range: 124..<136, value: UInt64(data.count), width: 11)
    // mtime: 136..148 (epoch). Deterministic timestamps would be nicer
    // but tar mtime doesn't appear in the signed payload's semantics
    // (we sign the tarball bytes verbatim, so as long as a given run is
    // consistent within itself, the client doesn't care).
    let mtime = UInt64(Date().timeIntervalSince1970)
    setOctal(in: &header, range: 136..<148, value: mtime, width: 11)
    // checksum placeholder: spaces, 148..156
    for i in 148..<156 { header[i] = 0x20 }
    // typeflag '0' regular file: 156
    header[156] = 0x30
    // magic "ustar  \0": 257..263 then version 263..265 "  "
    let magic: [UInt8] = [0x75, 0x73, 0x74, 0x61, 0x72, 0x20, 0x20, 0x00]
    for (i, b) in magic.enumerated() { header[257 + i] = b }

    // checksum: sum of all bytes in header, written into 148..155 as
    // 6 octal digits + NUL + space
    var sum: Int = 0
    for i in 0..<512 { sum += Int(header[i]) }
    let chk = String(format: "%06o", sum)
    for (i, c) in Array(chk.utf8).enumerated() { header[148 + i] = c }
    header[154] = 0x00
    header[155] = 0x20

    tar.append(header)
    tar.append(data)
    // pad to 512
    let pad = (512 - (data.count % 512)) % 512
    if pad > 0 { tar.append(Data(count: pad)) }
}

private func setOctal(in data: inout Data, range: Range<Int>, value: UInt64, width: Int) {
    let s = String(format: "%0\(width)o", value)
    let bytes = Array(s.utf8)
    var i = range.lowerBound
    for b in bytes {
        if i >= range.upperBound - 1 { break } // leave a trailing NUL
        data[i] = b
        i += 1
    }
    data[range.upperBound - 1] = 0x00
}

// MARK: - gzip via /usr/bin/gzip (macOS has this; CI macos-latest has it)

private func gzip(_ data: Data) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
    process.arguments = ["-9", "-n", "-c"]
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()

    let writeHandle = stdin.fileHandleForWriting
    try writeHandle.write(contentsOf: data)
    try writeHandle.close()

    let outData = try stdout.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let errData: Data = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
        throw TarError.gzipFailed(
            String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
        )
    }
    return outData
}
