import Foundation

/// Tiny helper around `/usr/bin/zip` for the two places Vakter needs to
/// build an archive: the EvidenceBundle (alarm-triggered, attached to
/// iMessage) and the Diagnostic Export (user-triggered from the Help
/// menu).
///
/// Why shell out to `/usr/bin/zip` instead of `Compression.framework`?
/// Foundation's compression API is per-file, not per-archive — to make
/// a real `.zip` you'd need to write your own PKZIP headers. `/usr/bin/zip`
/// is in `/usr/bin` on every macOS install since Big Sur, has been since
/// the dawn of time, and produces the exact format the receiving end
/// (iOS Files app, Finder) expects.
public enum Zipper {

    public enum Error: Swift.Error, LocalizedError {
        case zipNotFound
        case nonZeroExit(code: Int32, stderr: String)
        case noInputs

        public var errorDescription: String? {
            switch self {
            case .zipNotFound:               return "/usr/bin/zip is not available."
            case .nonZeroExit(let c, let e): return "/usr/bin/zip exited \(c): \(e)"
            case .noInputs:                  return "No files supplied to Zipper.zip."
            }
        }
    }

    /// Zip `inputs` into `outURL`. Paths inside the archive are relative
    /// to `baseDirectory` if provided, otherwise just the file basenames.
    ///
    /// Overwrites `outURL` if it already exists. `inputs` may include
    /// directories — `/usr/bin/zip -r` recurses into them.
    public static func zip(inputs: [URL],
                           to outURL: URL,
                           baseDirectory: URL? = nil) throws {
        guard !inputs.isEmpty else { throw Error.noInputs }
        let zipBin = URL(fileURLWithPath: "/usr/bin/zip")
        guard FileManager.default.isExecutableFile(atPath: zipBin.path) else {
            throw Error.zipNotFound
        }

        try? FileManager.default.removeItem(at: outURL)

        // If a base directory is supplied, run zip from that directory
        // with relative input paths. That way the archive contains
        // `photos/photo-01.jpg` instead of `/long/abs/path/photos/photo-01.jpg`.
        let cwd = baseDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let relInputs: [String] = inputs.map { url in
            if let base = baseDirectory,
               url.path.hasPrefix(base.path) {
                return String(url.path.dropFirst(base.path.count + 1))
            }
            return url.lastPathComponent
        }

        let p = Process()
        p.executableURL = zipBin
        p.currentDirectoryURL = cwd
        p.arguments = ["-r", "-q", outURL.path] + relInputs
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()

        if p.terminationStatus != 0 {
            let errText = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw Error.nonZeroExit(code: p.terminationStatus, stderr: errText)
        }
    }
}
