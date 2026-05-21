import Foundation

/// One persisted defenses-score sample, anchored to a calendar day.
public struct DefensesScoreSample: Codable, Sendable, Equatable, Identifiable {
    public let dayKey: String   // "yyyy-MM-dd" — keys the store
    public let score: Int       // 0–100
    public let timestamp: Date  // when the sample was taken

    public var id: String { dayKey }

    public init(dayKey: String, score: Int, timestamp: Date) {
        self.dayKey = dayKey
        self.score = score
        self.timestamp = timestamp
    }
}

/// Tracks the user's Defenses Audit score over time so the Settings page
/// can render a "you went from 50% → 90%" sparkline. One sample per
/// calendar day (we overwrite within-day samples so the sparkline tracks
/// the *latest* state per day, not every recheck).
public enum DefensesScoreHistory {

    /// Maximum number of days retained. Roughly 12 weeks of trend.
    public static let maxSamples = 84

    private static var url: URL {
        VakterConstants.supportDirectoryURL.appendingPathComponent("defenses-history.json")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Record a sample for today. If today's sample already exists, the
    /// score is overwritten with the latest value.
    public static func record(score: Int, at date: Date = Date()) {
        let today = dayFormatter.string(from: date)
        var samples = load()
        samples.removeAll { $0.dayKey == today }
        samples.append(DefensesScoreSample(dayKey: today, score: score, timestamp: date))
        // Keep newest N. Sort ascending by dayKey for stable storage.
        samples.sort { $0.dayKey < $1.dayKey }
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        save(samples)
    }

    public static func load() -> [DefensesScoreSample] {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode([DefensesScoreSample].self, from: data) else {
            return []
        }
        return s
    }

    private static func save(_ samples: [DefensesScoreSample]) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(samples)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[DefensesScoreHistory] save failed: %@", error.localizedDescription)
        }
    }
}
