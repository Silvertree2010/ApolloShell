import ApolloConfig

public struct SubscriptionToken: Hashable, Sendable {
    public let id: Int
}

struct StoreSnapshot: Sendable {
    let roots: [String: Value]

    func value(_ root: String, _ fields: [String]) -> Value {
        guard let base = roots[root] else { return .null }
        return SignalStore.read(base, fields)
    }
}

@MainActor
public final class SignalStore {
    private struct Subscription {
        let path: DependencyPath
        let onChange: @MainActor () -> Void
    }

    private var roots: [String: Value] = [:]
    private var subscriptions: [Int: Subscription] = [:]
    private var demandGroups: [Int: [DependencyPath]] = [:]
    private var demandCounts: [DependencyPath: Int] = [:]
    private var nextToken = 0
    private let scheduler: any FlushScheduler
    private var flushRequested = false
    private var demandObservers: [@MainActor (String) -> Void] = []
    private var demandSettleObservers: [@MainActor () -> Void] = []

    public var onDemandChange: (@MainActor (String) -> Void)? {
        get { demandObservers.first }
        set { demandObservers = newValue.map { [$0] } ?? [] }
    }
    public var onFlush: (@MainActor () -> Void)?
    public var onDemandSettle: (@MainActor () -> Void)? {
        get { demandSettleObservers.first }
        set { demandSettleObservers = newValue.map { [$0] } ?? [] }
    }

    public func addDemandObserver(_ observer: @escaping @MainActor (String) -> Void) {
        demandObservers.append(observer)
    }

    public func addDemandSettleObserver(_ observer: @escaping @MainActor () -> Void) {
        demandSettleObservers.append(observer)
    }

    public init(scheduler: any FlushScheduler) {
        self.scheduler = scheduler
    }

    public func value(_ path: DependencyPath) -> Value {
        guard let base = roots[path.root] else { return .null }
        return SignalStore.read(base, path.fields)
    }

    public func set(_ path: DependencyPath, _ value: Value) {
        let sanitized = SignalStore.sanitize(value)
        guard self.value(path) != sanitized else { return }
        let base = roots[path.root] ?? .record(Record())
        roots[path.root] = SignalStore.write(base, path.fields, sanitized)
        notify(path)
        requestFlush()
    }

    @discardableResult
    public func subscribe(_ path: DependencyPath, _ onChange: @escaping @MainActor () -> Void) -> SubscriptionToken {
        let token = nextToken
        nextToken += 1
        subscriptions[token] = Subscription(path: path, onChange: onChange)
        incrementDemand([path])
        return SubscriptionToken(id: token)
    }

    @discardableResult
    public func demand(_ paths: Set<DependencyPath>) -> SubscriptionToken {
        let token = nextToken
        nextToken += 1
        let ordered = Array(paths)
        demandGroups[token] = ordered
        incrementDemand(ordered)
        return SubscriptionToken(id: token)
    }

    public func unsubscribe(_ token: SubscriptionToken) {
        if let subscription = subscriptions.removeValue(forKey: token.id) {
            decrementDemand([subscription.path])
            return
        }
        if let paths = demandGroups.removeValue(forKey: token.id) {
            decrementDemand(paths)
        }
    }

    public func demandedPaths(root: String) -> Set<DependencyPath> {
        Set(demandCounts.keys.filter { $0.root == root })
    }

    private func incrementDemand(_ paths: [DependencyPath]) {
        var touchedRoots: [String] = []
        for path in paths {
            let count = demandCounts[path, default: 0]
            demandCounts[path] = count + 1
            if count == 0 {
                touchedRoots.append(path.root)
            }
        }
        for root in touchedRoots {
            for observer in demandObservers { observer(root) }
        }
    }

    private func decrementDemand(_ paths: [DependencyPath]) {
        var touchedRoots: [String] = []
        for path in paths {
            let count = demandCounts[path, default: 0] - 1
            if count <= 0 {
                demandCounts.removeValue(forKey: path)
                touchedRoots.append(path.root)
            } else {
                demandCounts[path] = count
            }
        }
        for root in touchedRoots {
            for observer in demandObservers { observer(root) }
        }
    }

    func snapshot() -> StoreSnapshot {
        StoreSnapshot(roots: roots)
    }

    private func notify(_ changed: DependencyPath) {
        for subscription in subscriptions.values where Self.related(subscription.path, changed) {
            subscription.onChange()
        }
    }

    func requestFlush() {
        guard !flushRequested else { return }
        flushRequested = true
        scheduler.requestFlush { [weak self] in
            guard let self else { return }
            self.flushRequested = false
            self.onFlush?()
            for observer in self.demandSettleObservers { observer() }
        }
    }

    private static func related(_ a: DependencyPath, _ b: DependencyPath) -> Bool {
        guard a.root == b.root else { return false }
        return isPrefix(a.fields, b.fields) || isPrefix(b.fields, a.fields)
    }

    private static func isPrefix(_ prefix: [String], _ fields: [String]) -> Bool {
        guard prefix.count <= fields.count else { return false }
        return Array(fields[0..<prefix.count]) == prefix
    }

    nonisolated static func read(_ value: Value, _ fields: [String]) -> Value {
        guard let first = fields.first else { return value }
        guard case .record(let record) = value, let next = record[first] else { return .null }
        return read(next, Array(fields.dropFirst()))
    }

    nonisolated static func write(_ value: Value, _ fields: [String], _ newValue: Value) -> Value {
        guard let first = fields.first else { return newValue }
        var record: Record
        if case .record(let existing) = value {
            record = existing
        } else {
            record = Record()
        }
        let child = record[first] ?? .null
        record[first] = write(child, Array(fields.dropFirst()), newValue)
        return .record(record)
    }

    nonisolated static func sanitize(_ value: Value) -> Value {
        switch value {
        case .number(let number):
            return number.isFinite ? value : .null
        case .list(let items):
            return .list(items.map(sanitize))
        case .record(let record):
            var sanitized = Record()
            for key in record.keys {
                sanitized[key] = sanitize(record[key] ?? .null)
            }
            return .record(sanitized)
        default:
            return value
        }
    }
}
