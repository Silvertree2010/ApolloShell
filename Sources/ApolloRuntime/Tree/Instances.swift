import Observation
import ApolloBase
import ApolloConfig
import ApolloStyle

public enum RuntimeLimits {
    public static let eachEntries = 5_000
    public static let elementsPerSurface = 20_000
    public static let elementDepth = 256
    public static let closeFeedbackTimeout: Double = 5
}

@MainActor
@Observable
public final class PropertyCell {
    public internal(set) var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    func update(_ newValue: Value) {
        if value != newValue {
            value = newValue
        }
    }
}

@MainActor
@Observable
public final class ElementInstance {
    public let identity: Identity
    public let kind: String
    public internal(set) var ir: ElementIR
    public internal(set) var properties: [String: PropertyCell] = [:]
    public internal(set) var arguments: [PropertyCell] = []
    public internal(set) var children: [ElementInstance] = []
    public internal(set) var slotChildren: [String: [ElementInstance]] = [:]
    public internal(set) var scope: LocalScope
    public var pseudo: PseudoState = [] {
        didSet {
            if pseudo != oldValue {
                onPseudoChange?(pseudo)
            }
        }
    }

    @ObservationIgnored var onPseudoChange: (@MainActor (PseudoState) -> Void)?

    init(identity: Identity, kind: String, ir: ElementIR, scope: LocalScope) {
        self.identity = identity
        self.kind = kind
        self.ir = ir
        self.scope = scope
    }

    public func property(_ name: String) -> Value {
        properties[name]?.value ?? .null
    }
}

@MainActor
@Observable
public final class SurfaceInstance {
    public let id: String
    public let screenKey: String
    public internal(set) var ir: SurfaceIR
    public internal(set) var properties: [String: PropertyCell] = [:]
    public internal(set) var root: [ElementInstance] = []
    public var isOpen: Bool
    public var isVisible: Bool

    init(id: String, screenKey: String, ir: SurfaceIR, isOpen: Bool) {
        self.id = id
        self.screenKey = screenKey
        self.ir = ir
        self.isOpen = isOpen
        self.isVisible = false
    }

    public func property(_ name: String) -> Value {
        properties[name]?.value ?? .null
    }
}

@MainActor
public protocol SurfaceHosting: AnyObject {
    func surfaceAdded(_ surface: SurfaceInstance)
    func surfaceChanged(_ surface: SurfaceInstance)
    func surfaceReplaced(_ surface: SurfaceInstance)
    func surfaceRemoved(id: String, screenKey: String)
}

public struct RuntimeStats: Sendable, Hashable {
    public var surfacesBuilt: Int
    public var elementsBuilt: Int
    public var bindingsEvaluated: Int
    public var providersRunning: Int

    public init(surfacesBuilt: Int = 0, elementsBuilt: Int = 0, bindingsEvaluated: Int = 0, providersRunning: Int = 0) {
        self.surfacesBuilt = surfacesBuilt
        self.elementsBuilt = elementsBuilt
        self.bindingsEvaluated = bindingsEvaluated
        self.providersRunning = providersRunning
    }
}
