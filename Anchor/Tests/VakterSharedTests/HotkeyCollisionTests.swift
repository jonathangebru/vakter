import XCTest
import Carbon.HIToolbox
@testable import VakterShared

/// Tests for the v0.9 system-shortcut collision guard.
///
/// Background: a user's saved binding of `⌘L` collided with macOS's
/// Lock-Screen system shortcut, which the OS intercepts before Carbon
/// can deliver the event to `HotkeyObserver`. The "hotkey doesn't
/// work" experience was the symptom. The fix has two layers:
///
///   - `HotkeyBinding.collidesWithReservedSystemShortcut` lists the
///     known-bad combos.
///   - `HotkeyStore.load()` substitutes `.default` and heals the
///     on-disk file when a collision is detected.
final class HotkeyCollisionTests: XCTestCase {

    func test_cmdL_isFlaggedAsColliding() {
        let b = HotkeyBinding(
            keyCode: UInt16(kVK_ANSI_L),
            modifiers: UInt32(cmdKey)
        )
        XCTAssertTrue(b.collidesWithReservedSystemShortcut,
                      "⌘L (macOS Lock Screen) must be flagged")
    }

    func test_cmdSpace_isFlaggedAsColliding() {
        let b = HotkeyBinding(
            keyCode: UInt16(kVK_Space),
            modifiers: UInt32(cmdKey)
        )
        XCTAssertTrue(b.collidesWithReservedSystemShortcut,
                      "⌘Space (Spotlight) must be flagged")
    }

    func test_cmdOptEsc_isFlaggedAsColliding() {
        let b = HotkeyBinding(
            keyCode: UInt16(kVK_Escape),
            modifiers: UInt32(cmdKey | optionKey)
        )
        XCTAssertTrue(b.collidesWithReservedSystemShortcut,
                      "⌘⌥Esc (Force Quit) must be flagged")
    }

    func test_default_isNotColliding() {
        XCTAssertFalse(HotkeyBinding.default.collidesWithReservedSystemShortcut,
                       "⌘⌃⌥L (shipped default) must be safe")
    }

    func test_cmdShiftL_isNotColliding() {
        // ⌘⇧L is NOT a system shortcut — should be allowed even though
        // it shares the L keycode with the bad ⌘L combo.
        let b = HotkeyBinding(
            keyCode: UInt16(kVK_ANSI_L),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        XCTAssertFalse(b.collidesWithReservedSystemShortcut)
    }

    func test_optV_isNotColliding() {
        // ⌥V — fine.
        let b = HotkeyBinding(
            keyCode: UInt16(kVK_ANSI_V),
            modifiers: UInt32(optionKey)
        )
        XCTAssertFalse(b.collidesWithReservedSystemShortcut)
    }

    /// The full end-to-end heal path: write a colliding binding to
    /// disk, then call `HotkeyStore.load()` and verify (a) it returns
    /// the default and (b) the file has been rewritten with the
    /// default so subsequent loads are quiet.
    func test_load_healsCollidingFile() throws {
        // Write a bad ⌘L binding to the real store path.
        let bad = HotkeyBinding(
            keyCode: UInt16(kVK_ANSI_L),
            modifiers: UInt32(cmdKey)
        )
        HotkeyStore.save(bad)

        // Load should NOT return ⌘L.
        let loaded = HotkeyStore.load()
        XCTAssertEqual(loaded, HotkeyBinding.default,
                       "load() must substitute the safe default")

        // And the file should now contain the default — second load
        // returns it without re-healing.
        let loaded2 = HotkeyStore.load()
        XCTAssertEqual(loaded2, HotkeyBinding.default)
    }
}
