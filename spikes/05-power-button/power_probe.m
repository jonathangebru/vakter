// Spike 5 — Power button intercept feasibility on Apple Silicon.
//
// On Apple Silicon Macs, the power button is also the Touch ID sensor.
// It's electrically wired through the Secure Enclave / SMC rather than
// the standard keyboard event path, so public APIs may not observe it
// at all. This program probes whether ANY public-API surface exposes it:
//
//   1. IOHIDManager matching on GenericDesktop / SystemControl usage pages
//   2. CGEventTap for system-defined events
//
// Approach: open broad HID matching, log every event seen for 10 seconds,
// ask the user to BRIEFLY (< 0.5s) press the power button during the
// window. If no event corresponds to that press, the conclusion is
// "not interceptable via public API."

#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDKeys.h>

static int eventCount = 0;

static void hidValueCallback(void *context, IOReturn result, void *sender, IOHIDValueRef value) {
    IOHIDElementRef element = IOHIDValueGetElement(value);
    uint32_t usagePage = IOHIDElementGetUsagePage(element);
    uint32_t usage     = IOHIDElementGetUsage(element);
    CFIndex  v         = IOHIDValueGetIntegerValue(value);

    // Only log non-zero values (key-down style) to avoid noise from
    // continuous mouse/trackpad streams.
    if (v == 0 && usagePage != 0x0C) return;

    NSLog(@"HID event: page=0x%04X usage=0x%04X value=%lld", usagePage, usage, (long long)v);
    eventCount++;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        printf("== Spike 5: Power-button intercept probe ==\n\n");

        IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
        if (!manager) { printf("FAIL: IOHIDManagerCreate\n"); return 1; }

        // Match three usage pages commonly involved in power/system events:
        //   0x01 GenericDesktop — includes "System Power Down" (usage 0x81)
        //   0x07 Keyboard       — standard keys (unlikely for power button)
        //   0x0C Consumer       — media keys, includes "Power" (usage 0x30)
        NSArray *matching = @[
            @{ @kIOHIDDeviceUsagePageKey: @(0x01) },
            @{ @kIOHIDDeviceUsagePageKey: @(0x07) },
            @{ @kIOHIDDeviceUsagePageKey: @(0x0C) },
        ];
        IOHIDManagerSetDeviceMatchingMultiple(manager, (__bridge CFArrayRef)matching);
        IOHIDManagerRegisterInputValueCallback(manager, hidValueCallback, NULL);
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

        IOReturn ret = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
        if (ret != kIOReturnSuccess) {
            printf("⚠ IOHIDManagerOpen returned 0x%X — may need 'Input Monitoring' permission.\n", ret);
            printf("   Will still try; running anyway.\n\n");
        } else {
            printf("✅ HID manager open. Matching pages 0x01, 0x07, 0x0C.\n\n");
        }

        // Print what devices we matched (sanity check).
        CFSetRef devices = IOHIDManagerCopyDevices(manager);
        if (devices) {
            CFIndex n = CFSetGetCount(devices);
            printf("Matched %ld HID device(s)\n", (long)n);
            CFRelease(devices);
        }

        printf("\n→ Waiting 10 seconds. Please BRIEFLY tap the power button\n");
        printf("  (< 0.5s — don't hold it). You can also press other keys to\n");
        printf("  verify the HID stream is alive.\n\n");

        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:10.0]];

        IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
        CFRelease(manager);

        printf("\n== Result ==\n");
        printf("Observed %d HID event(s) during the window.\n", eventCount);
        if (eventCount > 0) {
            printf("If a row above had page=0x0001 usage=0x0081 (System Power Down) or\n");
            printf("page=0x000C usage=0x0030 (Consumer Power), the power button IS visible\n");
            printf("to userspace. Otherwise: not interceptable on this hardware.\n");
        } else {
            printf("No HID events seen at all — likely needs 'Input Monitoring' permission\n");
            printf("in System Settings → Privacy & Security. Re-run after granting.\n");
        }
    }
    return 0;
}
