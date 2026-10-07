import ApolloBase

public enum StyleOrigin: Int, Sendable, Hashable, Comparable {
    case base
    case config
    case user
    case inline

    public static func < (lhs: StyleOrigin, rhs: StyleOrigin) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct PseudoState: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let hover = PseudoState(rawValue: 1 << 0)
    public static let active = PseudoState(rawValue: 1 << 1)
    public static let focus = PseudoState(rawValue: 1 << 2)
    public static let checked = PseudoState(rawValue: 1 << 3)
    public static let disabled = PseudoState(rawValue: 1 << 4)
    public static let open = PseudoState(rawValue: 1 << 5)
    public static let firstChild = PseudoState(rawValue: 1 << 6)
    public static let lastChild = PseudoState(rawValue: 1 << 7)
    public static let invalid = PseudoState(rawValue: 1 << 8)
    public static let overflowing = PseudoState(rawValue: 1 << 9)

    static let byName: [String: PseudoState] = [
        "hover": .hover,
        "active": .active,
        "focus": .focus,
        "checked": .checked,
        "disabled": .disabled,
        "open": .open,
        "first-child": .firstChild,
        "last-child": .lastChild,
        "invalid": .invalid,
        "overflowing": .overflowing,
    ]
}

public struct StyleSubject: Sendable, Hashable {
    public var kind: String
    public var id: String?
    public var classes: [String]
    public var pseudo: PseudoState

    public init(kind: String, id: String? = nil, classes: [String] = [], pseudo: PseudoState = []) {
        self.kind = kind
        self.id = id
        self.classes = classes
        self.pseudo = pseudo
    }
}

public struct Declaration: Sendable, Hashable {
    public var property: String
    public var rawValue: String
    public var important: Bool
    public var span: SourceSpan

    public init(property: String, rawValue: String, important: Bool, span: SourceSpan) {
        self.property = property
        self.rawValue = rawValue
        self.important = important
        self.span = span
    }
}

public enum CSSColor: Sendable, Hashable {
    case rgba(red: Double, green: Double, blue: Double, alpha: Double)
    case system(name: String, alpha: Double)
    case currentColor
}

public struct CSSLength: Sendable, Hashable {
    public var value: Double
    public var unit: CSSUnit

    public init(value: Double, unit: CSSUnit) {
        self.value = value
        self.unit = unit
    }

    public init(_ value: Double, _ unit: CSSUnit) {
        self.init(value: value, unit: unit)
    }
}

public enum CSSUnit: Sendable, Hashable {
    case points
    case percent
    case fraction
    case auto
}

public struct GradientStop: Sendable, Hashable {
    public var color: CSSColor
    public var position: Double?

    public init(color: CSSColor, position: Double?) {
        self.color = color
        self.position = position
    }
}

public struct LinearGradient: Sendable, Hashable {
    public var angleDegrees: Double
    public var stops: [GradientStop]

    public init(angleDegrees: Double, stops: [GradientStop]) {
        self.angleDegrees = angleDegrees
        self.stops = stops
    }
}

public enum GlassVariant: String, Sendable, Hashable {
    case regular
    case clear
}

public enum MaterialThickness: String, Sendable, Hashable {
    case ultraThin = "ultra-thin"
    case thin
    case regular
    case thick
    case ultraThick = "ultra-thick"
    case bar
}

public enum BackgroundLayer: Sendable, Hashable {
    case color(CSSColor)
    case gradient(LinearGradient)
    case image(path: String)
    case glass(GlassVariant, tint: CSSColor?)
    case material(MaterialThickness)
}

public enum TimingCurve: Sendable, Hashable {
    case linear
    case cubicBezier(Double, Double, Double, Double)
    case spring(response: Double, damping: Double)
}

public struct Transition: Sendable, Hashable {
    public var property: String
    public var duration: Double
    public var curve: TimingCurve

    public init(property: String, duration: Double, curve: TimingCurve) {
        self.property = property
        self.duration = duration
        self.curve = curve
    }
}

public enum AppearEffect: Sendable, Hashable {
    case fade
    case scale(Double)
    case slide(edge: String, distance: Double?)
    case blur(Double)
}

public struct AppearTransition: Sendable, Hashable {
    public var effects: [AppearEffect]
    public var duration: Double
    public var curve: TimingCurve

    public init(effects: [AppearEffect], duration: Double, curve: TimingCurve) {
        self.effects = effects
        self.duration = duration
        self.curve = curve
    }
}

public enum CSSValue: Sendable, Hashable {
    case keyword(String)
    case number(Double)
    case length(CSSLength)
    case lengths([CSSLength])
    case angle(Double)
    case duration(Double)
    case color(CSSColor)
    case layers([BackgroundLayer])
    case transitions([Transition])
    case appear([AppearTransition])
    case shadows([Shadow])
    case transform([TransformOperation])
    case fontFamilies([String])
    case filters([FilterOperation])
    case animation(name: String, duration: Double, repeatCount: Double?)
    case gridColumns([CSSLength])
    case span(Int)
    case border(width: Double, dashed: Bool, color: CSSColor)
}

public struct Shadow: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var blur: Double
    public var spread: Double
    public var color: CSSColor

    public init(x: Double, y: Double, blur: Double, spread: Double, color: CSSColor) {
        self.x = x
        self.y = y
        self.blur = blur
        self.spread = spread
        self.color = color
    }
}

public enum TransformOperation: Sendable, Hashable {
    case rotate(Double)
    case scale(Double)
    case translate(Double, Double)
}

public enum FilterOperation: Sendable, Hashable {
    case dropShadow(Shadow)
    case blur(Double)
}

public struct ComputedStyle: Sendable, Hashable {
    public internal(set) var values: [String: CSSValue]
    public internal(set) var customProperties: [String: String]

    public init(values: [String: CSSValue] = [:]) {
        self.values = values
        self.customProperties = [:]
    }

    public subscript(property: String) -> CSSValue? { values[property] }

    public func setting(_ property: String, _ value: CSSValue?) -> ComputedStyle {
        var copy = self
        copy.values[property] = value
        return copy
    }
}

public struct CSSPropertySchema: Sendable, Hashable {
    public var name: String
    public var inherits: Bool
    public var initial: CSSValue?
    public var feature: String

    public init(name: String, inherits: Bool, initial: CSSValue?, feature: String) {
        self.name = name
        self.inherits = inherits
        self.initial = initial
        self.feature = feature
    }
}
