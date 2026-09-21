import ApplicationServices
import Foundation
import Synchronization

/// Talks to one app on its own thread.
///
/// Every Accessibility call is a synchronous round trip into the app. Made
/// on the main thread, one slow app (Spotify re-laying out a web page) held
/// up the animation of every other window and even the mouse. Each app now
/// has a serial queue of its own, and the main thread only drops off work.
///
/// Frames are latest-wins: while the app is still busy with one frame, newer
/// frames for the same window replace each other in the mailbox instead of
/// queuing up, so a slow app skips frames rather than falling behind.
final class AppWorker: Sendable {
    let pid: pid_t
    private let queue: DispatchQueue

    private struct Job {
        let window: AXWindow
        var frame: CGRect
        var completions: [@MainActor @Sendable () -> Void]
    }

    private struct State {
        var jobs: [CGWindowID: Job] = [:]
        var order: [CGWindowID] = []
        var running = false
        var dropped = 0
    }

    private let state = Mutex(State())
    /// Called on the main thread for a window whose frame could not be set.
    private let onFailure: @MainActor @Sendable (CGWindowID) -> Void

    init(pid: pid_t, onFailure: @escaping @MainActor @Sendable (CGWindowID) -> Void) {
        self.pid = pid
        self.onFailure = onFailure
        queue = DispatchQueue(label: "apollowm.app.\(pid)", qos: .userInteractive)
    }

    /// Frames replaced before the app got to them (the app was too slow).
    var droppedFrames: Int { state.withLock { $0.dropped } }

    func resetStats() { state.withLock { $0.dropped = 0 } }

    /// Queues `frame` for `window`, replacing a frame not yet written.
    /// `completion` runs on the main thread once it (or a newer one) is set.
    func setFrame(_ window: AXWindow, _ frame: CGRect,
                  completion: (@MainActor @Sendable () -> Void)? = nil) {
        let start = state.withLock { state -> Bool in
            let id = window.windowID
            if var job = state.jobs[id] {
                job.frame = frame
                if let completion { job.completions.append(completion) }
                state.jobs[id] = job
                state.dropped += 1
            } else {
                state.jobs[id] = Job(window: window, frame: frame, completions: completion.map { [$0] } ?? [])
                state.order.append(id)
            }
            if state.running { return false }
            state.running = true
            return true
        }
        if start { queue.async { self.drain() } }
    }

    /// Runs other work for this app (raise, focus) on its thread.
    func run(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    private func drain() {
        while true {
            let jobs = state.withLock { state -> [Job] in
                let jobs = state.order.compactMap { state.jobs[$0] }
                state.jobs.removeAll()
                state.order.removeAll()
                if jobs.isEmpty { state.running = false }
                return jobs
            }
            if jobs.isEmpty { return }
            for job in jobs {
                let ok = job.window.setFrame(job.frame)
                let id = job.window.windowID
                let completions = job.completions
                let onFailure = self.onFailure
                if !ok || !completions.isEmpty {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            if !ok { onFailure(id) }
                            for completion in completions { completion() }
                        }
                    }
                }
            }
        }
    }
}
