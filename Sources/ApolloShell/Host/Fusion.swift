import AppKit
import SwiftUI
import ApolloStyle
import ApolloRuntime
import ApolloShellCore

struct FusionSettings: Equatable {
    var shape: FusionShape
    var jelly: JellyStrength
    var speed: Double
    var reduceMotion: Bool

    var isOn: Bool { shape.style != .separate }

    static let standard = FusionSettings(tokens: .empty, reduceMotion: false)

    init(tokens: TokenEnvironment, reduceMotion: Bool) {
        let standard = FusionShape.standard
        let style = tokens.value("--apollo-fusion-style").flatMap { FusionStyle(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
        let radius = tokens.value("--apollo-fusion-radius").flatMap { ThemeValueReader.number($0, unit: .points) }
        let edge = tokens.value("--apollo-fusion-screen-edge").flatMap { FusionScreenEdge(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
        shape = FusionShape(style: style ?? standard.style, innerRadius: CGFloat(min(48, max(0, radius ?? Double(standard.innerRadius)))), screenEdge: edge ?? standard.screenEdge)
        jelly = tokens.value("--apollo-jelly").flatMap { JellyStrength(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) } ?? .subtle
        speed = tokens.animationsEnabled ? tokens.animationSpeed : 0
        self.reduceMotion = reduceMotion
    }

    var springs: JellySpringParameters? {
        JellySpringParameters(strength: jelly, speed: speed, reduceMotion: reduceMotion)
    }
}

struct FusionMember: Equatable {
    var group: String
    var fill: Bool
    var screenKey: String
    var side: JellySide?
    var radius: CGFloat
    var calm: Bool
    var level: NSWindow.Level
    var order: Int
}

@MainActor
@Observable
final class FusionSkinModel {
    var pieces: [FusionPiece] = []
    var shape = FusionShape.standard
    var fill = ComputedStyle(values: [:])
    var size = CGSize.zero
}

@MainActor
final class FusionCoordinator: BackgroundPainter, AuxiliaryWindowOwner {
    static let calmLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
    static let raisedLevel = NSWindow.Level.statusBar
    static let group = "fusion"
    let ownerID = "fusion"

    private(set) var settings = FusionSettings.standard
    private(set) var fields: [String: JellyField] = [:]
    private(set) var models: [String: FusionSkinModel] = [:]
    private var screens: [String: ScreenGeometry] = [:]
    private var sides: [String: JellySide?] = [:]
    private var owners: [String: String] = [:]
    private var tickers: [String: any FrameTicker] = [:]
    private var lastTick: [String: TimeInterval] = [:]
    var member: @MainActor (String) -> FusionMember? = { _ in nil }
    var fillStyle: @MainActor (String) -> ComputedStyle = { _ in ComputedStyle(values: [:]) }
    var makeTicker: @MainActor (String) -> (any FrameTicker)? = { _ in nil }
    var context: RenderContext?
    private(set) var ticks = 0

    var isOn: Bool { settings.isOn }

    func apply(_ next: FusionSettings) {
        settings = next
        for key in fields.keys {
            fields[key]?.parameters = next.springs
            models[key]?.shape = next.shape
            publish(key)
        }
        if !next.isOn {
            for ticker in tickers.values { ticker.stop() }
            tickers.removeAll()
            fields.removeAll()
            owners.removeAll()
        }
    }

    func background(for surface: SurfaceInstance, style: ComputedStyle) -> BackgroundChoice {
        guard isOn, !Self.groupName(surface).isEmpty else { return .standard }
        return .suppressed
    }

    static func groupName(_ surface: SurfaceInstance) -> String {
        surface.property("fuse-group").plainText ?? ""
    }

    func frameChanged(_ key: String, _ frame: CGRect) {
        guard isOn else { return }
        let owner = key.split(separator: "#").first.map(String.init) ?? key
        guard let member = member(owner) else { return }
        let piece = key == owner ? member.radius : nil
        place(key, owner: owner, member: member, frame: frame, radius: piece)
    }

    func flyouts(_ owner: String, _ pieces: [(key: String, rect: CGRect, radius: CGFloat, side: JellySide)]) {
        guard isOn, let member = member(owner) else { return }
        let wanted = Set(pieces.map { owner + "#" + $0.key })
        for (key, screen) in owners where key.hasPrefix(owner + "#") && !wanted.contains(key) {
            remove(key, screen: screen, into: sides[key] ?? nil)
        }
        for piece in pieces {
            let key = owner + "#" + piece.key
            sides[key] = piece.side
            place(key, owner: owner, member: member, frame: piece.rect, radius: piece.radius, side: piece.side)
        }
    }

    private func place(_ key: String, owner: String, member: FusionMember, frame: CGRect, radius: CGFloat?, side: JellySide? = nil) {
        let screen = member.screenKey
        let clipped = screens[screen].map { frame.intersection($0.frame) } ?? frame
        if frame.isNull || clipped.isNull || clipped.width < 0.5 || clipped.height < 0.5 {
            remove(key, screen: screen, into: side ?? member.side)
            return
        }
        if let old = owners[key], old != screen { remove(key, screen: old, into: nil) }
        owners[key] = screen
        if sides[key] == nil { sides[key] = side ?? member.side }
        var field = fields[screen] ?? JellyField(parameters: settings.springs)
        field.set(key, rect: clipped, radius: radius ?? member.radius, grow: side ?? member.side)
        fields[screen] = field
        changed(screen)
    }

    private func remove(_ key: String, screen: String, into side: JellySide?) {
        guard owners[key] != nil else { return }
        owners[key] = nil
        fields[screen]?.remove(key, into: side)
        changed(screen)
    }

    func screensChanged(_ geometries: [String: ScreenGeometry]) {
        screens = geometries
        for key in fields.keys where geometries[key] == nil {
            tickers[key]?.stop()
            tickers[key] = nil
            fields[key] = nil
            models[key] = nil
            owners = owners.filter { $0.value != key }
        }
        for key in fields.keys { publish(key) }
    }

    private func changed(_ screen: String) {
        publish(screen)
        guard let field = fields[screen] else { return }
        if field.isResting {
            tickers[screen]?.stop()
            tickers[screen] = nil
        } else if tickers[screen] == nil, let ticker = makeTicker(screen) {
            tickers[screen] = ticker
            lastTick[screen] = nil
            ticker.start { [weak self] elapsed in
                self?.tick(screen, elapsed) ?? false
            }
        }
    }

    func tick(_ screen: String, _ elapsed: TimeInterval) -> Bool {
        ticks += 1
        let dt = lastTick[screen].map { elapsed - $0 } ?? 1.0 / 120
        lastTick[screen] = elapsed
        fields[screen]?.step(dt)
        publish(screen)
        let going = !(fields[screen]?.isResting ?? true)
        if !going {
            tickers[screen] = nil
            lastTick[screen] = nil
        }
        return going
    }

    func tick(_ screen: String, by seconds: TimeInterval) {
        fields[screen]?.step(seconds)
        publish(screen)
    }

    func model(_ screen: String) -> FusionSkinModel {
        if let existing = models[screen] { return existing }
        let model = FusionSkinModel()
        model.shape = settings.shape
        models[screen] = model
        return model
    }

    private func publish(_ screen: String) {
        guard let geometry = screens[screen] else { return }
        let model = model(screen)
        let frame = geometry.frame
        let pieces = (fields[screen]?.pieces ?? []).map { entry in
            FusionPiece(rect: CGRect(x: entry.piece.rect.minX - frame.minX, y: frame.maxY - entry.piece.rect.maxY,
                                     width: entry.piece.rect.width, height: entry.piece.rect.height), radius: entry.piece.radius)
        }
        if model.pieces != pieces { model.pieces = pieces }
        if model.shape != settings.shape { model.shape = settings.shape }
        if model.size != frame.size { model.size = frame.size }
        let fill = fillStyle(screen)
        if model.fill != fill { model.fill = fill }
    }

    func pieces(on screen: String) -> [JellyField.Entry] {
        fields[screen]?.pieces ?? []
    }

    func raised(on screen: String) -> Bool {
        owners.contains { key, value in
            guard value == screen, !key.contains("#"), let member = member(key) else { return false }
            return member.calm && member.level.rawValue >= Self.raisedLevel.rawValue
        }
    }

    func level(for key: String, base: NSWindow.Level) -> NSWindow.Level {
        guard isOn, let member = member(key), member.calm, raised(on: member.screenKey) else { return base }
        return NSWindow.Level(rawValue: max(base.rawValue, Self.raisedLevel.rawValue + 1))
    }

    func windows(on screen: ScreenGeometry) -> [AuxiliaryWindowSpec] {
        guard isOn else { return [] }
        return [AuxiliaryWindowSpec(id: "skin", frame: screen.frame, level: raised(on: screen.key) ? Self.raisedLevel : Self.calmLevel)]
    }

    func content(for id: String, screen: ScreenGeometry) -> AnyView {
        guard let context else { return AnyView(EmptyView()) }
        return AnyView(FusionSkinView(model: model(screen.key), context: context))
    }

    static func side(anchor: String?) -> JellySide? {
        switch anchor {
        case "left", "top-left": .minX
        case "right", "top-right": .maxX
        case "top": .maxY
        case "bottom", "bottom-right", "bottom-left": .minY
        default: nil
        }
    }

    static func side(_ flyout: FlyoutSide) -> JellySide {
        switch flyout {
        case .right: .minX
        case .left: .maxX
        case .top: .minY
        case .bottom: .maxY
        }
    }

    static func contentDelay(_ springs: JellySpringParameters?, share: Double = 0.8) -> TimeInterval {
        guard let springs else { return 0 }
        var field = JellyField(parameters: springs)
        field.set("probe", rect: CGRect(x: 0, y: 0, width: 100, height: 100), radius: 0, grow: .minX)
        var time = 0.0
        while time < 2 {
            let width = field.pieces.first?.piece.rect.width ?? 100
            if width >= 100 * share { return time }
            field.step(1.0 / 240)
            time += 1.0 / 240
        }
        return time
    }
}

struct FusionSkinShape: Shape {
    var pieces: [FusionPiece]
    var shape: FusionShape
    var screen: CGRect

    func path(in rect: CGRect) -> Path {
        Path(FusedOutline.path(pieces, screen: screen, shape: shape))
    }
}

struct FusionSkinView: View {
    let model: FusionSkinModel
    let context: RenderContext

    var body: some View {
        let screen = CGRect(origin: .zero, size: model.size)
        Color.clear
            .frame(width: model.size.width, height: model.size.height)
            .modifier(StyledBox(style: model.fill, context: context, padded: false,
                                form: AnyShape(FusionSkinShape(pieces: model.pieces, shape: model.shape, screen: screen))))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
    }
}

@MainActor
final class JellyAnimator: SurfaceAnimator {
    let name = "jelly"
    static let fadeIn: TimeInterval = 0.14
    static let fadeOut: TimeInterval = 0.12
    let springs: @MainActor () -> JellySpringParameters?

    init(springs: @escaping @MainActor () -> JellySpringParameters?) {
        self.springs = springs
    }

    func closedTransform(_ geometry: MotionGeometry) -> CATransform3D { CATransform3DIdentity }
    func transformAnimation(opening: Bool) -> CAAnimation? { nil }

    func fade(opening: Bool) -> (duration: TimeInterval, curve: CAMediaTimingFunction) {
        (opening ? Self.fadeIn : Self.fadeOut, CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1))
    }

    func fadeDelay(opening: Bool) -> TimeInterval {
        opening ? FusionCoordinator.contentDelay(springs()) : 0
    }

    func duration(opening: Bool) -> TimeInterval {
        opening ? fadeDelay(opening: true) + Self.fadeIn : Self.fadeOut
    }

    func progress(at time: TimeInterval, opening: Bool) -> Double { opening ? 1 : 0 }

    func visibleFrame(open frame: CGRect, geometry: MotionGeometry, progress: Double) -> CGRect {
        progress > 0.5 ? frame : .null
    }
}
