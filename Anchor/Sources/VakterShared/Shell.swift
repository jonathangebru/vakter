import Foundation

/// Tiny shell-out helper. Replaces ~8 ad-hoc `Process()` + `Pipe()` +
/// `readDataToEndOfFile()` blocks that had spread across the codebase.
///
/// Examples:
///   `Shell.run("/usr/sbin/nvram", ["fmm-mobileme-token-FMM"])`
///   `Shell.run("/usr/bin/defaults", ["read", "MobileMeAccounts", "Accounts"])`
///
/// Errors are swallowed — callers each have their own opinion on what
/// "missing binary" or "non-zero exit" means (e.g. `DefensesProbe`
/// treats "not found" as "feature disabled"). For workflows that DO
/// care about the exit code, use `runDetailed(...)` which returns the
/// status code alongside the combined output.
public enum Shell {

    /// Run `binary` with `arguments` and return combined stdout+stderr
    /// as UTF-8 (empty string on any failure).
    @discardableResult
    public static func run(_ binary: String, _ arguments: [String] = []) -> String {
        runDetailed(binary, arguments).output
    }

    /// Run a binary and return `(output, exitCode)`. Exit code is -1
    /// if the process couldn't be launched at all.
    public static func runDetailed(_ binary: String,
                                   _ arguments: [String] = []) -> (output: String, exitCode: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
        } catch {
            return ("", -1)
        }
        p.waitUntilExit()

        let outText = String(
            data: out.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8) ?? ""
        let errText = String(
            data: err.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8) ?? ""
        return (outText + errText, p.terminationStatus)
    }
}
