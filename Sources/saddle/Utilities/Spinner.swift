import CLICore
import Foundation

final class BrailleSpinner: @unchecked Sendable {
    private static let frames = ["\u{280B}", "\u{2819}", "\u{2839}", "\u{2838}", "\u{283C}", "\u{2834}", "\u{2826}", "\u{2827}", "\u{2807}", "\u{280F}"]
    private var running = false
    private let done = DispatchSemaphore(value: 0)
    private let label: String?

    init(label: String? = nil) {
        self.label = label
    }

    func start() {
        guard isatty(STDOUT_FILENO) != 0 else { return }
        running = true
        let ready = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            var i = 0
            while self.running {
                let frame = Self.frames[i % Self.frames.count]
                if let label = self.label {
                    print("\(styled(frame, .cyan)) \(styled(label, .dim))", terminator: "")
                } else {
                    print(" \(styled(frame, .dim))", terminator: "")
                }
                fflush(stdout)
                if i == 0 { ready.signal() }
                Thread.sleep(forTimeInterval: 0.08)
                print("\u{1B}[2K\u{1B}[G", terminator: "")
                fflush(stdout)
                i += 1
            }
            self.done.signal()
        }
        ready.wait()
    }

    func stop() {
        guard running else { return }
        running = false
        done.wait()
    }
}

final class ProgressSpinner: @unchecked Sendable {
    private static let frames = ["\u{280B}", "\u{2819}", "\u{2839}", "\u{2838}", "\u{283C}", "\u{2834}", "\u{2826}", "\u{2827}", "\u{2807}", "\u{280F}"]
    private var running = false
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var _label: String = ""

    var label: String {
        get { lock.withLock { _label } }
        set { lock.withLock { _label = newValue } }
    }

    func start() {
        guard isatty(STDOUT_FILENO) != 0 else { return }
        running = true
        let ready = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            var i = 0
            while self.running {
                let frame = Self.frames[i % Self.frames.count]
                let currentLabel = self.label
                print("\(styled(frame, .cyan)) \(currentLabel)", terminator: "")
                fflush(stdout)
                if i == 0 { ready.signal() }
                Thread.sleep(forTimeInterval: 0.08)
                print("\u{1B}[2K\u{1B}[G", terminator: "")
                fflush(stdout)
                i += 1
            }
            self.done.signal()
        }
        ready.wait()
    }

    func stop() {
        guard running else { return }
        running = false
        done.wait()
    }
}
