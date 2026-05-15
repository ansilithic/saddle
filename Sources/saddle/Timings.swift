import Foundation

/// Per-repo rolling-window timing storage. One JSON file per repo under
/// `~/Library/Application Support/com.ansilithic.saddle/timings/<owner-repo>.json`.
/// Workers never share files, so the writes are naturally parallel-safe.
///
/// Stats use median + MAD (median absolute deviation) — robust to one-off
/// slow runs (e.g., a cold container build) so the adaptive timeout doesn't
/// chase outliers.
struct Timings {
    static let windowSize = 30
    static let minSamplesForStats = 10

    struct Snapshot: Codable {
        var samples: [Double] = []
        var lastDuration: Double?
        var lastTimestamp: String?
    }

    struct Stats {
        let count: Int
        let median: Double
        let mad: Double
        let p90: Double
        let last: Double?
    }

    // MARK: - Persistence

    static var dir: String { "\(Paths.dataDir)/timings" }

    static func path(for url: String) -> String {
        let base = URLHelpers.hookBaseName(from: url)
        return "\(dir)/\(base).json"
    }

    static func load(for url: String) -> Snapshot {
        guard let data = try? FS.readFile(path(for: url)).data(using: .utf8),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot()
        }
        return snap
    }

    /// Append a successful run's duration to the rolling window. Failures
    /// shouldn't enter the stats — they'd skew the median artificially.
    static func record(url: String, duration: Double) {
        ensureDir()
        var snap = load(for: url)
        snap.samples.append(duration)
        if snap.samples.count > windowSize {
            snap.samples.removeFirst(snap.samples.count - windowSize)
        }
        snap.lastDuration = duration
        snap.lastTimestamp = DateFormatting.iso8601.string(from: Date())
        write(snap, for: url)
    }

    private static func write(_ snap: Snapshot, for url: String) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snap)
            guard let json = String(data: data, encoding: .utf8) else { return }
            try FS.writeFile(path(for: url), contents: json)
        } catch {
            Log.error("Failed to write timings for \(url): \(error)")
        }
    }

    private static func ensureDir() {
        if !FS.isDirectory(dir) {
            try? FS.createDirectory(dir)
        }
    }

    // MARK: - Stats

    static func stats(for url: String) -> Stats? {
        let snap = load(for: url)
        guard !snap.samples.isEmpty else { return nil }
        let m = median(snap.samples)
        let absDev = snap.samples.map { abs($0 - m) }
        return Stats(
            count: snap.samples.count,
            median: m,
            mad: median(absDev),
            p90: percentile(snap.samples, 0.90),
            last: snap.lastDuration
        )
    }

    /// Return enforcement timeout in seconds, or nil if there isn't enough
    /// data yet. Generous: only kills the truly stuck.
    static func adaptiveTimeout(for url: String) -> TimeInterval? {
        guard let s = stats(for: url), s.count >= minSamplesForStats else { return nil }
        return max(60.0, s.median + 8.0 * s.mad)
    }

    // MARK: - Stats helpers

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let idx = max(0, min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.down))))
        return sorted[idx]
    }
}
