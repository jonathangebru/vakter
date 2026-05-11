import Foundation
import IOKit
import IOKit.pwr_mgt
import AnchorShared

/// Observes the MacBook's clamshell (lid) state via IOPMrootDomain.
///
/// Implementation ported from `spikes/03-clamshell/lid_test.m` — verified
/// working on Apple Silicon macOS 14.8.5 on 2026-05-11. See SPIKE_REPORT.md.
///
/// The kernel sends a general-interest notification on any IOPMrootDomain
/// state change; we re-read `AppleClamshellState` on each notification to
/// determine which side of the transition we're on.
final class LidObserver: AnchorSignalObserver {

    private var rootDomain: io_registry_entry_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var lastClosed: Bool?
    private var emit: ((AnchorSignal) -> Void)?

    func start(_ emit: @escaping (AnchorSignal) -> Void) {
        self.emit = emit

        rootDomain = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard rootDomain != 0 else {
            NSLog("[LidObserver] FAIL: IOPMrootDomain not found")
            return
        }

        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        if let port = notifyPort,
           let runLoopSource = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }

        let opaque = Unmanaged.passUnretained(self).toOpaque()
        let kr = IOServiceAddInterestNotification(
            notifyPort,
            rootDomain,
            kIOGeneralInterest,
            { (refcon, _, _, _) in
                guard let refcon = refcon else { return }
                let me = Unmanaged<LidObserver>.fromOpaque(refcon).takeUnretainedValue()
                me.readAndPublish()
            },
            opaque,
            &notifier
        )
        if kr != KERN_SUCCESS {
            NSLog("[LidObserver] IOServiceAddInterestNotification failed: %d", kr)
            return
        }

        // Prime the cache so first transition is detected correctly.
        readAndPublish(initial: true)
        NSLog("[LidObserver] watching IOPMrootDomain general-interest")
    }

    private func readAndPublish(initial: Bool = false) {
        guard let prop = IORegistryEntryCreateCFProperty(
            rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Bool else { return }

        let closed = prop
        defer { lastClosed = closed }

        // First read primes state; no event.
        if initial || lastClosed == nil { return }
        if closed == lastClosed { return }

        emit?(closed ? .lidClosed : .lidOpened)
    }

    deinit {
        if notifier != 0 { IOObjectRelease(notifier) }
        if rootDomain != 0 { IOObjectRelease(rootDomain) }
        if let port = notifyPort { IONotificationPortDestroy(port) }
    }
}
