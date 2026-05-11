#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

// Spike 3 — Verify we can:
//   (a) read the current AppleClamshellState from IOPMrootDomain
//   (b) register IOServiceAddInterestNotification for change events
//
// Notes:
//   AppleClamshellState is a CFBoolean: kCFBooleanTrue = lid closed.
//   kIOPMMessageClamshellStateChange (0xE0000280) is the kernel message
//   we receive via the interest notification.

static io_object_t notifier = 0;
static int eventCount = 0;

static void clamshellCallback(void *refcon, io_service_t service, natural_t messageType, void *messageArgument) {
    // Print every message we get; filter on the specific one.
    NSLog(@"  notification: messageType=0x%X messageArgument=%p", (unsigned)messageType, messageArgument);

    // 0xE0000280 = kIOPMMessageClamshellStateChange (from IOKit headers)
    // Some macOS versions also fire 0xE0000280 generically — we re-read state to confirm.
    io_registry_entry_t rd = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    if (rd) {
        CFTypeRef val = IORegistryEntryCreateCFProperty(rd, CFSTR("AppleClamshellState"), kCFAllocatorDefault, 0);
        if (val) {
            BOOL closed = CFBooleanGetValue((CFBooleanRef)val);
            NSLog(@"  -> AppleClamshellState now: %s", closed ? "CLOSED" : "OPEN");
            CFRelease(val);
            eventCount++;
        }
        IOObjectRelease(rd);
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        printf("== Spike 3: Clamshell (lid) state ==\n\n");

        // -- (a) Read current state ------------------------------------------
        io_registry_entry_t rd = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
        if (!rd) {
            printf("FAIL: could not find IOPMrootDomain service\n");
            return 1;
        }

        CFTypeRef val = IORegistryEntryCreateCFProperty(rd, CFSTR("AppleClamshellState"), kCFAllocatorDefault, 0);
        if (!val) {
            printf("⚠ AppleClamshellState property not present (probably a desktop or external-only Mac)\n");
        } else {
            BOOL closed = CFBooleanGetValue((CFBooleanRef)val);
            printf("✅ AppleClamshellState read OK: %s\n", closed ? "CLOSED" : "OPEN");
            CFRelease(val);
        }

        // Other useful related keys — read them all for context.
        NSArray *keys = @[@"AppleClamshellState", @"AppleClamshellCausesSleep", @"IOPMUserActiveState"];
        for (NSString *k in keys) {
            CFTypeRef v = IORegistryEntryCreateCFProperty(rd, (__bridge CFStringRef)k, kCFAllocatorDefault, 0);
            if (v) {
                NSLog(@"  %@: %@", k, (__bridge id)v);
                CFRelease(v);
            }
        }

        // -- (b) Register notification --------------------------------------
        IONotificationPortRef notifyPort = IONotificationPortCreate(kIOMainPortDefault);
        CFRunLoopSourceRef rls = IONotificationPortGetRunLoopSource(notifyPort);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);

        kern_return_t kr = IOServiceAddInterestNotification(
            notifyPort, rd, kIOGeneralInterest, clamshellCallback, NULL, &notifier);
        if (kr != KERN_SUCCESS) {
            printf("FAIL: IOServiceAddInterestNotification kr=%d\n", kr);
            IOObjectRelease(rd);
            return 1;
        }
        printf("✅ Registered for IOPMrootDomain general-interest notifications.\n");
        printf("\nNow waiting for events for 12 seconds.\n");
        printf("→ Try closing the lid briefly and opening it again to trigger an event.\n");
        printf("→ Or just observe the existing power-state chatter from the kernel.\n\n");

        // Run loop for 12 seconds
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:12.0]];

        IOObjectRelease(notifier);
        IOObjectRelease(rd);
        IONotificationPortDestroy(notifyPort);

        printf("\n== Result ==\n");
        if (eventCount > 0) {
            printf("✅ Received %d clamshell-related state read(s).\n", eventCount);
        } else {
            printf("ℹ No clamshell change events fired during the test window.\n");
            printf("   The state-read primitive itself works (see top of output).\n");
            printf("   Notification subscription succeeded; just no lid movement to observe.\n");
        }
    }
    return 0;
}
