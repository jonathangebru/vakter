#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

static AudioObjectID defaultOutputDevice(void) {
    AudioObjectID deviceID = 0;
    UInt32 size = sizeof(deviceID);
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus s = AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, &deviceID);
    if (s != noErr) { fprintf(stderr, "default device query failed: %d\n", (int)s); return 0; }
    return deviceID;
}

static NSString *deviceName(AudioObjectID id) {
    CFStringRef name = NULL;
    UInt32 size = sizeof(name);
    AudioObjectPropertyAddress addr = {
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus s = AudioObjectGetPropertyData(id, &addr, 0, NULL, &size, &name);
    if (s != noErr || name == NULL) return @"?";
    NSString *result = [(__bridge NSString *)name copy];
    CFRelease(name);
    return result;
}

static BOOL readVolume(AudioObjectID id, Float32 *out) {
    UInt32 size = sizeof(Float32);
    AudioObjectPropertyAddress addr = {
        kAudioDevicePropertyVolumeScalar,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    OSStatus s = AudioObjectGetPropertyData(id, &addr, 0, NULL, &size, out);
    return s == noErr;
}

static OSStatus writeVolume(AudioObjectID id, Float32 value) {
    AudioObjectPropertyAddress addr = {
        kAudioDevicePropertyVolumeScalar,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    return AudioObjectSetPropertyData(id, &addr, 0, NULL, sizeof(Float32), &value);
}

static BOOL readMute(AudioObjectID id, UInt32 *out) {
    UInt32 size = sizeof(UInt32);
    AudioObjectPropertyAddress addr = {
        kAudioDevicePropertyMute,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    OSStatus s = AudioObjectGetPropertyData(id, &addr, 0, NULL, &size, out);
    return s == noErr;
}

static OSStatus writeMute(AudioObjectID id, UInt32 value) {
    AudioObjectPropertyAddress addr = {
        kAudioDevicePropertyMute,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    return AudioObjectSetPropertyData(id, &addr, 0, NULL, sizeof(UInt32), &value);
}

// Walk all devices, look for built-in / internal speakers by name.
static AudioObjectID internalSpeakersDevice(void) {
    UInt32 size = 0;
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus s = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, NULL, &size);
    if (s != noErr) return 0;
    UInt32 count = size / sizeof(AudioObjectID);
    AudioObjectID *ids = (AudioObjectID *)malloc(size);
    s = AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, ids);
    AudioObjectID found = 0;
    if (s == noErr) {
        for (UInt32 i = 0; i < count; i++) {
            NSString *n = [deviceName(ids[i]) lowercaseString];
            if ([n containsString:@"macbook"] && [n containsString:@"speaker"]) { found = ids[i]; break; }
            if ([n containsString:@"built-in output"]) { found = ids[i]; break; }
            if ([n containsString:@"internal speakers"]) { found = ids[i]; break; }
        }
    }
    free(ids);
    return found;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        printf("== Spike 1: CoreAudio volume control ==\n\n");

        AudioObjectID dev = defaultOutputDevice();
        if (dev == 0) { printf("FAIL: no default output device\n"); return 1; }
        printf("Default output: %s (id=%u)\n", deviceName(dev).UTF8String, dev);

        Float32 v = 0;
        if (readVolume(dev, &v)) printf("  current volume: %.2f%%\n", v * 100);
        else printf("  ⚠ volume API unsupported on this device\n");

        UInt32 m = 0;
        if (readMute(dev, &m)) printf("  current mute:   %s\n", m == 1 ? "muted" : "unmuted");
        else printf("  ⚠ mute API unsupported on this device\n");

        AudioObjectID internalID = internalSpeakersDevice();
        if (internalID != 0) printf("Internal speakers detected: %s (id=%u)\n", deviceName(internalID).UTF8String, internalID);
        else printf("⚠ Could not identify internal speakers by name\n");

        printf("\n-- Round-trip test (will restore original state) --\n");
        Float32 origVol = v;
        UInt32 origMute = m;

        OSStatus s1 = writeMute(dev, 0);
        printf("setMute(0) -> %s\n", s1 == noErr ? "OK" : "ERR");

        Float32 targetVol = (origVol > 0.5f) ? 0.3f : 0.7f;
        OSStatus s2 = writeVolume(dev, targetVol);
        printf("setVolume(%.2f) -> %s\n", targetVol, s2 == noErr ? "OK" : "ERR");
        Float32 readBack = 0;
        readVolume(dev, &readBack);
        printf("  read back: %.2f%%\n", readBack * 100);
        BOOL confirmed = fabsf(readBack - targetVol) < 0.02f;
        printf("  matches?  %s\n", confirmed ? "YES" : "NO");

        OSStatus s3 = writeVolume(dev, 1.0f);
        printf("setVolume(1.00) -> %s\n", s3 == noErr ? "OK" : "ERR");
        readVolume(dev, &readBack);
        printf("  read back: %.2f%%\n", readBack * 100);

        writeVolume(dev, origVol);
        writeMute(dev, origMute);
        printf("Restored: vol=%.2f%% mute=%u\n", origVol * 100, origMute);

        printf("\n== Result ==\n");
        if (s2 == noErr && s3 == noErr && confirmed) {
            printf("✅ CoreAudio volume control WORKS without entitlements.\n");
            printf("✅ Mute/unmute control WORKS.\n");
            printf("→ Audio strategy primitives are viable on this Mac.\n");
        } else {
            printf("❌ One or more operations failed — see details above.\n");
        }
    }
    return 0;
}
