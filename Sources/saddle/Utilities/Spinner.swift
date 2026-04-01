#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import CLICore
import Foundation

final class ProgressSpinner: @unchecked Sendable {
    private static let frames = ["\u{280B}", "\u{2819}", "\u{2839}", "\u{2838}", "\u{283C}", "\u{2834}", "\u{2826}", "\u{2827}", "\u{2807}", "\u{280F}"]
    private var running = false
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var _label: String = ""
    private var _status: String = ""
    private var _summary: String = ""
    private var _pending: [String] = []

    // Feed system
    private enum ItemState { case active, completed, failed }
    private struct FeedItem {
        let id: String
        let name: String
        let startTime: CFAbsoluteTime
        var endTime: CFAbsoluteTime?
        var state: ItemState
        var detail: String?
    }
    private var _feedItems: [String: FeedItem] = [:]
    private var _feedActive = false
    private var _maxFeedLines: Int = 30

    /// Main spinner line — animated with braille frame while running,
    /// printed static (with checkmark) when stopped.
    var label: String {
        get { lock.withLock { _label } }
        set { lock.withLock { _label = newValue } }
    }

    /// Sub-line below the label — live counter/stats. Cleared on stop.
    var status: String {
        get { lock.withLock { _status } }
        set { lock.withLock { _status = newValue } }
    }

    /// Printed below the persisted label after stop.
    var summary: String {
        get { lock.withLock { _summary } }
        set { lock.withLock { _summary = newValue } }
    }

    var maxFeedLines: Int {
        get { lock.withLock { _maxFeedLines } }
        set { lock.withLock { _maxFeedLines = newValue } }
    }

    func emit(_ line: String) {
        lock.withLock { _pending.append(line) }
    }

    func activate(_ id: String, name: String) {
        lock.withLock {
            _feedActive = true
            _feedItems[id] = FeedItem(id: id, name: name, startTime: CFAbsoluteTimeGetCurrent(), endTime: nil, state: .active, detail: nil)
        }
    }

    func complete(_ id: String) {
        lock.withLock {
            _feedItems[id]?.state = .completed
            _feedItems[id]?.endTime = CFAbsoluteTimeGetCurrent()
        }
    }

    func fail(_ id: String, reason: String) {
        let sanitized = reason
            .split(separator: "\n", omittingEmptySubsequences: true)
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? reason
        lock.withLock {
            _feedItems[id]?.state = .failed
            _feedItems[id]?.endTime = CFAbsoluteTimeGetCurrent()
            _feedItems[id]?.detail = sanitized
        }
    }

    private func drainPending() -> [String] {
        lock.withLock {
            let lines = _pending
            _pending = []
            return lines
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m)m\(s)s"
    }

    private func styledFeedName(_ name: String, style: Color) -> String {
        guard let lastSlash = name.lastIndex(of: "/") else {
            return styled(name, style)
        }
        let prefix = String(name[name.startIndex...lastSlash])
        let repoName = String(name[name.index(after: lastSlash)...])
        return styled(prefix, .darkGray) + styled(repoName, style)
    }

    private func styledElapsed(_ seconds: TimeInterval) -> String {
        let text = formatDuration(seconds) + ".."
        if seconds < 5 { return styled(text, .dim) }
        if seconds < 15 { return styled(text, .yellow) }
        return styled(text, .red)
    }

    private func buildSubLines() -> [String] {
        var lines: [String] = []

        // Status line (counter/stats)
        let currentStatus = lock.withLock { _status }
        if !currentStatus.isEmpty {
            lines.append("  " + currentStatus)
        }

        // Feed items
        let feedActive = lock.withLock { _feedActive }
        if feedActive {
            lines.append(contentsOf: buildFeedLines())
        }

        return lines
    }

    private func buildFeedLines() -> [String] {
        let now = CFAbsoluteTimeGetCurrent()
        let maxLines: Int

        lock.lock()
        _feedItems = _feedItems.filter { (_, item) in
            guard let endTime = item.endTime else { return true }
            let age = now - endTime
            switch item.state {
            case .active: return true
            case .completed: return age < 2.0
            case .failed: return age < 8.0
            }
        }
        let snapshot = Array(_feedItems.values)
        maxLines = _maxFeedLines
        lock.unlock()

        var notifications: [(FeedItem, CFAbsoluteTime)] = []
        var actives: [FeedItem] = []

        for item in snapshot {
            switch item.state {
            case .active:
                actives.append(item)
            case .completed:
                let age = now - (item.endTime ?? now)
                notifications.append((item, age))
            case .failed:
                let age = now - (item.endTime ?? now)
                notifications.append((item, age))
            }
        }

        notifications.sort { $0.1 < $1.1 }
        actives.sort { $0.startTime < $1.startTime }

        var lines: [String] = []

        for (item, age) in notifications {
            let duration = (item.endTime ?? now) - item.startTime
            let durationStr = formatDuration(duration)

            switch item.state {
            case .completed:
                if age < 1.4 {
                    lines.append("  " + styled("\u{2713}", .dim) + " " + styled(item.name, .dim) + "  " + styled(durationStr, .dim))
                } else {
                    lines.append("  " + styled("\u{2713}", .darkGray) + " " + styled(item.name, .darkGray) + "  " + styled(durationStr, .darkGray))
                }
            case .failed:
                let reason = item.detail ?? ""
                let reasonPart = reason.isEmpty ? "" : "  " + styled(reason, .dim)
                if age < 4.0 {
                    lines.append("  " + styled("\u{2716}", .red) + " " + styledFeedName(item.name, style: .bold) + reasonPart + "  " + styled(durationStr, .dim))
                } else {
                    lines.append("  " + styled("\u{2716}", .dim) + " " + styled(item.name, .dim) + reasonPart + "  " + styled(durationStr, .dim))
                }
            case .active:
                break
            }
        }

        for item in actives {
            let elapsed = now - item.startTime
            lines.append("  " + styledFeedName(item.name, style: .bold) + "  " + styledElapsed(elapsed))
        }

        if lines.count > maxLines {
            lines = Array(lines.prefix(maxLines))
        }

        return lines
    }

    private func clearLines(_ extraLines: Int) {
        var seq = "\u{1B}[2K"
        for _ in 0..<extraLines {
            seq += "\u{1B}[1A\u{1B}[2K"
        }
        seq += "\u{1B}[G"
        print(seq, terminator: "")
        fflush(stdout)
    }

    func start() {
        guard isatty(STDOUT_FILENO) != 0 else { return }
        running = true
        let ready = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            var i = 0
            while self.running {
                let pending = self.drainPending()
                for line in pending {
                    print(line)
                    fflush(stdout)
                }

                let frame = Self.frames[i % Self.frames.count]
                let currentLabel = self.label
                let subLines = self.buildSubLines()

                print("\(styled(frame, .cyan)) \(currentLabel)", terminator: "")
                for line in subLines {
                    print("\n\(line)", terminator: "")
                }
                fflush(stdout)
                if i == 0 { ready.signal() }
                Thread.sleep(forTimeInterval: 0.08)
                self.clearLines(subLines.count)

                i += 1
            }

            // Persist the label as a static line (checkmark instead of braille)
            let finalLabel = self.label
            if !finalLabel.isEmpty {
                print("  \(finalLabel)")
                fflush(stdout)
            }

            let remaining = self.drainPending()
            for line in remaining {
                print(line)
                fflush(stdout)
            }

            self.done.signal()
        }
        ready.wait()
    }

    func stop() {
        if running {
            running = false
            done.wait()
        }
        let s = lock.withLock { _summary }
        if !s.isEmpty {
            print(s)
            fflush(stdout)
        }
    }
}
