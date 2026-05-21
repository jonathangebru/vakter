import SwiftUI
import AppKit
import VakterShared

// Local tint so the recorder picks up the Vakter palette without
// fishing through VakterDesign's full namespace.
private enum RecorderTone {
    static let active = Color(red: 0.10, green: 0.20, blue: 0.36) // matches VakterDesign.anchor
}

/// A SwiftUI key-combo recorder.
///
/// Behaviour:
///   - Renders as a labelled button showing the current binding (e.g. ⌘⌃⌥L).
///   - On click, enters "recording" mode: the label flips to "Press any
///     combination…", a global key monitor catches the next key-down
///     event, and the combo is captured.
///   - Bindings without any modifier (just a letter) are rejected with a
///     short message so the user doesn't bind a typeable key.
///   - Escape cancels recording without changing the binding.
///
/// The actual key capture is done by AppKit via `NSEvent.addLocalMonitor…`
/// — SwiftUI's `.onKeyPress` only works in focused views and doesn't
/// observe modifier-only events reliably across macOS versions.
struct KeyRecorder: View {

    @Binding var binding: HotkeyBinding
    @State private var isRecording = false
    @State private var hint: String = ""
    @State private var monitor: Any?

    /// Called whenever the user accepts a new binding. Use this to call
    /// `HotkeyStore.save(...)` and `helperClient.reloadHotkey()`.
    var onChange: (HotkeyBinding) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { toggleRecording() }) {
                HStack(spacing: 8) {
                    if isRecording {
                        // Calm pulsing dot in Vakter's brand navy — red
                        // would conflict with the alarm semantic and
                        // make the recorder feel like an emergency.
                        Image(systemName: "circle.fill")
                            .foregroundStyle(RecorderTone.active)
                        Text("Press any combination…")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "command")
                        Text(binding.displayLabel)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                    }
                    Spacer()
                    if !isRecording {
                        Text("Click to change")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Esc to cancel")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isRecording ? RecorderTone.active.opacity(0.5)
                                                  : Color.secondary.opacity(0.3),
                                      lineWidth: isRecording ? 2 : 1)
                )
            }
            .buttonStyle(.plain)

            if !hint.isEmpty {
                // Hint copy uses the same secondary tone as the rest of
                // the Settings copy — orange would imply an error state
                // that doesn't exist (the user just needs to add a
                // modifier).
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stopRecording() }
    }

    // MARK: - Recording

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        hint = ""
        isRecording = true

        // Local monitor: catches key-downs while our app is frontmost.
        // Plenty for the Settings window. If the user clicks "Record"
        // and then immediately presses their chosen combo, AppKit
        // dispatches the event through this monitor before any other
        // handler can swallow it.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc cancels without saving.
            if event.keyCode == 53 { // kVK_Escape — hardcoded to avoid pulling Carbon into the app target
                stopRecording()
                return nil
            }

            let cocoaFlags = event.modifierFlags.rawValue
            let mods = carbonModifiers(fromCocoa: cocoaFlags)
            let candidate = HotkeyBinding(keyCode: event.keyCode, modifiers: mods)

            guard candidate.hasModifier else {
                hint = "Pick a combo with ⌘, ⌃, ⌥ or ⇧ — otherwise it'd fire while typing."
                return nil
            }

            self.binding = candidate
            self.onChange(candidate)
            stopRecording()
            return nil  // swallow the event so it doesn't propagate
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
