import ApolloBase
import ApolloConfig

@MainActor
public struct ProviderContext {
    public let publish: @MainActor (_ fields: [String], _ value: Value) -> Void
    public let emit: @MainActor (_ event: String, _ fields: Record) -> Void
    public let warn: @MainActor (Diagnostic) -> Void
}

@MainActor
public protocol ProviderInstance: AnyObject {
    var schema: ProviderSchema { get }
    func start(_ context: ProviderContext)
    func demandChanged(_ demanded: Set<DependencyPath>)
    func configure(_ settings: Record)
    func perform(_ action: String, arguments: [Value], properties: Record) async throws -> Value
    func stop()
}

@MainActor
public final class ProviderHost {
    private struct RunningState {
        var isRunning = false
        var demanded: Set<DependencyPath> = []
    }

    private let store: SignalStore
    private var providers: [String: any ProviderInstance] = [:]
    private var running: [String: RunningState] = [:]
    private var awakeCounts: [String: Int] = [:]
    private var awakeGroups: [Int: String] = [:]
    private var dirtyProviders: Set<String> = []
    private var nextToken = 0

    public private(set) var startCount = 0
    public private(set) var stopCount = 0
    public var onEvent: (@MainActor (String, Record) -> Void)?
    public var onWarning: (@MainActor (Diagnostic) -> Void)?

    public init(store: SignalStore) {
        self.store = store
        store.onDemandChange = { [weak self] root in
            self?.markDirty(root)
        }
        store.onDemandSettle = { [weak self] in
            self?.reconcile()
        }
    }

    public func register(_ provider: any ProviderInstance) {
        let id = provider.schema.id
        providers[id] = provider
        running[id] = RunningState()
        markDirty(id)
    }

    public func provider(_ id: String) -> (any ProviderInstance)? {
        providers[id]
    }

    public func configure(_ id: String, _ settings: Record) {
        providers[id]?.configure(settings)
    }

    public var runningProviderCount: Int {
        running.values.filter(\.isRunning).count
    }

    @discardableResult
    public func keepAwake(_ providerID: String) -> SubscriptionToken {
        let token = nextToken
        nextToken += 1
        awakeGroups[token] = providerID
        awakeCounts[providerID, default: 0] += 1
        markDirty(providerID)
        return SubscriptionToken(id: token)
    }

    public func unsubscribe(_ token: SubscriptionToken) {
        guard let providerID = awakeGroups.removeValue(forKey: token.id) else { return }
        let count = (awakeCounts[providerID] ?? 1) - 1
        if count <= 0 {
            awakeCounts.removeValue(forKey: providerID)
        } else {
            awakeCounts[providerID] = count
        }
        markDirty(providerID)
    }

    private func markDirty(_ providerID: String) {
        guard providers[providerID] != nil else { return }
        dirtyProviders.insert(providerID)
        store.requestFlush()
    }

    private func reconcile() {
        guard !dirtyProviders.isEmpty else { return }
        let ids = dirtyProviders
        dirtyProviders.removeAll()
        for id in ids {
            guard let provider = providers[id], var state = running[id] else { continue }
            let demanded = store.demandedPaths(root: id)
            let hasDemand = !demanded.isEmpty || awakeCounts[id, default: 0] > 0
            if hasDemand && !state.isRunning {
                state.isRunning = true
                state.demanded = demanded
                running[id] = state
                provider.start(context(for: id))
                provider.demandChanged(demanded)
                startCount += 1
            } else if hasDemand && state.isRunning {
                if state.demanded != demanded {
                    state.demanded = demanded
                    running[id] = state
                    provider.demandChanged(demanded)
                }
            } else if !hasDemand && state.isRunning {
                state.isRunning = false
                state.demanded = []
                running[id] = state
                provider.stop()
                stopCount += 1
            }
        }
    }

    private func context(for id: String) -> ProviderContext {
        ProviderContext(
            publish: { [weak self] fields, value in
                self?.store.set(DependencyPath(id, fields), value)
            },
            emit: { [weak self] event, fields in
                self?.onEvent?(event, fields)
            },
            warn: { [weak self] diagnostic in
                self?.onWarning?(diagnostic)
            }
        )
    }
}
