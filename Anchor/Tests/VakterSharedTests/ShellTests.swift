import XCTest
@testable import VakterShared

/// Tests for the `Shell` helper that consolidates 8 ad-hoc Process()
/// shell-out blocks. Verifies (a) the happy path returns expected
/// output, (b) errors degrade gracefully, (c) `runDetailed` exposes
/// the exit code.
final class ShellTests: XCTestCase {

    /// `echo` is universally available and produces deterministic output.
    func test_run_returnsEcho() {
        let out = Shell.run("/bin/echo", ["hello vakter"])
        XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines),
                       "hello vakter")
    }

    /// Missing binary degrades to empty string (no throw).
    func test_run_missingBinaryReturnsEmpty() {
        let out = Shell.run("/nope/does/not/exist", [])
        XCTAssertEqual(out, "")
    }

    /// `runDetailed` surfaces a non-zero exit code without crashing.
    func test_runDetailed_capturesNonZeroExit() {
        // `false` is the canonical "always exits 1" binary.
        let result = Shell.runDetailed("/usr/bin/false", [])
        XCTAssertEqual(result.exitCode, 1)
    }

    /// `runDetailed` returns -1 when the binary doesn't exist.
    func test_runDetailed_missingBinaryReturnsMinusOne() {
        let result = Shell.runDetailed("/nope/does/not/exist", [])
        XCTAssertEqual(result.exitCode, -1)
    }

    /// `true` exits 0; the helper should report it.
    func test_runDetailed_capturesZeroExit() {
        let result = Shell.runDetailed("/usr/bin/true", [])
        XCTAssertEqual(result.exitCode, 0)
    }
}
