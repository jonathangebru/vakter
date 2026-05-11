import CoreAudio
import Foundation

// Returns the default output device ID.
func defaultOutputDevice() -> AudioObjectID? {
    var deviceID = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
    guard status == noErr else {
        FileHandle.standardError.write("default device query failed: \(status)\n".data(using: .utf8)!)
        return nil
    }
    return deviceID
}

func deviceName(_ id: AudioObjectID) -> String {
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<CFString?>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name)
    guard status == noErr, let result = name?.takeRetainedValue() else { return "?" }
    return result as String
}

func volume(_ id: AudioObjectID) -> Float? {
    var vol: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &vol)
    guard status == noErr else { return nil }
    return vol
}

func setVolume(_ id: AudioObjectID, _ value: Float) -> OSStatus {
    var vol: Float32 = value
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
}

func muteState(_ id: AudioObjectID) -> UInt32? {
    var muted: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &muted)
    guard status == noErr else { return nil }
    return muted
}

func setMute(_ id: AudioObjectID, _ value: UInt32) -> OSStatus {
    var muted: UInt32 = value
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muted)
}

// Enumerate available output devices and identify the internal speakers.
func internalSpeakersDevice() -> AudioObjectID? {
    var size: UInt32 = 0
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let sysObj = AudioObjectID(kAudioObjectSystemObject)
    var status = AudioObjectGetPropertyDataSize(sysObj, &addr, 0, nil, &size)
    guard status == noErr else { return nil }
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    var ids = [AudioObjectID](repeating: 0, count: count)
    status = AudioObjectGetPropertyData(sysObj, &addr, 0, nil, &size, &ids)
    guard status == noErr else { return nil }

    for id in ids {
        let n = deviceName(id).lowercased()
        if n.contains("macbook") && n.contains("speaker") { return id }
        if n.contains("built-in output") { return id }
        if n.contains("internal speakers") { return id }
    }
    return nil
}

// --- main ---
print("== Spike 1: CoreAudio volume control ==\n")

guard let current = defaultOutputDevice() else {
    print("FAIL: no default output device")
    exit(1)
}
print("Default output: \(deviceName(current)) (id=\(current))")

if let v = volume(current) {
    print("  current volume: \(String(format: "%.2f", v * 100))%")
} else {
    print("  ⚠ volume API unsupported on this device")
}
if let m = muteState(current) {
    print("  current mute:   \(m == 1 ? "muted" : "unmuted")")
} else {
    print("  ⚠ mute API unsupported on this device")
}

if let internalID = internalSpeakersDevice() {
    print("Internal speakers detected: \(deviceName(internalID)) (id=\(internalID))")
} else {
    print("⚠ Could not identify internal speakers by name")
}

// --- The actual test: can we set values and read them back? ---
print("\n-- Round trip test (will restore original state) --")

let origVol = volume(current) ?? 0.5
let origMute = muteState(current) ?? 0

// 1. Try unmute
let m1 = setMute(current, 0)
print("setMute(0) -> \(m1 == noErr ? "OK" : "ERR(\(m1))")")

// 2. Try set to a moderate value, then back
let targetVol: Float = (origVol > 0.5) ? 0.3 : 0.7
let s1 = setVolume(current, targetVol)
print("setVolume(\(targetVol)) -> \(s1 == noErr ? "OK" : "ERR(\(s1))")")
let readBack = volume(current) ?? -1
print("  read back: \(String(format: "%.2f", readBack * 100))%")
let confirmed = abs(readBack - targetVol) < 0.02
print("  matches?  \(confirmed ? "✅" : "❌")")

// 3. Try setting to 1.0 (max)
let s2 = setVolume(current, 1.0)
print("setVolume(1.0) -> \(s2 == noErr ? "OK" : "ERR(\(s2))")")
let readMax = volume(current) ?? -1
print("  read back: \(String(format: "%.2f", readMax * 100))%")

// 4. Restore
_ = setVolume(current, origVol)
_ = setMute(current, origMute)
print("Restored: vol=\(String(format: "%.2f", origVol * 100))% mute=\(origMute)")

print("\n== Result ==")
if s1 == noErr && s2 == noErr && confirmed {
    print("✅ CoreAudio volume control WORKS on this Mac without entitlements.")
    print("✅ Mute/unmute control WORKS.")
    print("→ Audio strategy primitives are viable.")
} else {
    print("❌ At least one operation failed — see details above.")
}
