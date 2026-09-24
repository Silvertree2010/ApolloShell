import ApolloRuntime

@MainActor
public final class ProviderTimers {
    private final class Entry {
        let interval: Double
        var work: ScheduledWork?
        var action: @MainActor () -> Void

        init(interval: Double, action: @escaping @MainActor () -> Void) {
            self.interval = interval
            self.action = action
        }
    }

    private let clock: any RuntimeClock
    private var entries: [String: Entry] = [:]

    public init(clock: any RuntimeClock) {
        self.clock = clock
    }

    public func set(_ key: String, every interval: Double, active: Bool, immediately: Bool = false, _ action: @escaping @MainActor () -> Void) {
        if !active {
            cancel(key)
            return
        }
        if let existing = entries[key], existing.interval == interval {
            existing.action = action
            return
        }
        cancel(key)
        let entry = Entry(interval: interval, action: action)
        entries[key] = entry
        if immediately { action() }
        guard entries[key] === entry else { return }
        schedule(key, entry)
    }

    public func once(_ key: String, after seconds: Double, _ action: @escaping @MainActor () -> Void) {
        cancel(key)
        let entry = Entry(interval: 0, action: action)
        entries[key] = entry
        entry.work = clock.schedule(after: max(seconds, 0)) { [weak self, weak entry] in
            guard let self, let entry, self.entries[key] === entry else { return }
            self.entries[key] = nil
            entry.action()
        }
    }

    public func isActive(_ key: String) -> Bool {
        entries[key] != nil
    }

    public func cancel(_ key: String) {
        entries.removeValue(forKey: key)?.work?.cancel()
    }

    public func cancelAll() {
        for entry in entries.values { entry.work?.cancel() }
        entries.removeAll()
    }

    private func schedule(_ key: String, _ entry: Entry) {
        entry.work = clock.schedule(after: entry.interval) { [weak self, weak entry] in
            guard let self, let entry, self.entries[key] === entry else { return }
            entry.action()
            guard self.entries[key] === entry else { return }
            self.schedule(key, entry)
        }
    }
}
