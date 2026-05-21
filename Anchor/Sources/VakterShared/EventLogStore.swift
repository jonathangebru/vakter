import Foundation

/// Persistent JSON-lines event log. One row per state transition.
///
/// The helper appends; the menubar app's Event Log view reads the tail.
/// Concurrent access is serialised through `queue`.
public final class EventLogStore: @unchecked Sendable {

    public static let shared = EventLogStore()

    private let queue = DispatchQueue(label: "app.vakter.mac.eventlog", qos: .utility)
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL = VakterConstants.eventLogURL) {
        self.url = url
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        // Ensure directory exists.
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    public func append(_ event: VakterEvent) {
        queue.sync {
            do {
                let line = try encoder.encode(event)
                var data = Data()
                data.append(line)
                data.append(0x0A) // newline

                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: url)
                }
            } catch {
                NSLog("EventLogStore.append failed: \(error)")
            }
        }
    }

    /// Read the most recent `limit` events, newest first.
    public func recent(limit: Int = 30) -> [VakterEvent] {
        queue.sync {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
                return []
            }
            let lines = raw.split(separator: "\n").reversed()
            var out: [VakterEvent] = []
            out.reserveCapacity(limit)
            for line in lines {
                guard out.count < limit else { break }
                guard let data = line.data(using: .utf8) else { continue }
                if let event = try? decoder.decode(VakterEvent.self, from: data) {
                    out.append(event)
                }
            }
            return out
        }
    }
}
