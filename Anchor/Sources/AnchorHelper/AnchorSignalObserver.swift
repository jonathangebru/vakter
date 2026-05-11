import Foundation
import AnchorShared

/// Common interface for everything that produces `AnchorSignal` values
/// (lid sensor, power, Bluetooth, hotkey, future: power button).
///
/// Observers own their own lifetime. They're started once at daemon launch
/// and run until the process exits.
protocol AnchorSignalObserver: AnyObject {
    /// Begin emitting signals. The handler may be invoked from any thread.
    func start(_ emit: @escaping (AnchorSignal) -> Void)
}
