import AppKit
import ApolloConfig
import ApolloRuntime

struct SurfaceWindowSpec: Equatable {
    enum ClickThrough: Equatable {
        case off, on, auto
    }

    enum CloseTrigger: String, CaseIterable {
        case outsideClick = "outside-click"
        case escape
        case focusLoss = "focus-loss"
        case mouseLeave = "mouse-leave"
        case globalEscape = "global-escape"
    }

    var kind: String
    var layer: String
    var level: NSWindow.Level
    var behavior: NSWindow.CollectionBehavior
    var keyboard: Bool
    var clickThrough: ClickThrough
    var sticky: Bool
    var hideInFullscreen: Bool
    var overhang: Bool
    var safeArea: Bool
    var reserve: Bool
    var motion: String
    var scrim: Double?
    var closeOn: Set<CloseTrigger>
    var hoverEdge: Bool
    var hoverMargin: CGFloat
    var hoverGap: CGFloat
    var group: String?
    var timeout: Double?
    var title: String
    var titleVisible: Bool
    var titlebar: Bool
    var resizable: Bool
    var closable: Bool
    var miniaturizable: Bool
    var autosave: String?

    static let closeOnDefault: Set<CloseTrigger> = [.outsideClick, .escape, .focusLoss]

    @MainActor init(surface: SurfaceInstance) {
        self.init(kind: surface.ir.kind, property: surface.property)
    }

    init(kind: String, property: (String) -> Value) {
        self.kind = kind
        let layer = Self.text(property("layer")) ?? SurfaceWindowKind.defaultLayer(kind)
        self.layer = layer
        let scrim = Self.number(property("scrim")).map { min(1, max(0, $0)) }
        self.scrim = kind == "popup" ? scrim : nil
        var level = SurfaceWindowKind.level(layer, kind: kind)
        if self.scrim != nil, layer == "popup" { level = NSWindow.Level(rawValue: level.rawValue + 1) }
        self.level = level
        let sticky = Self.bool(property("sticky")) ?? true
        self.sticky = sticky
        behavior = SurfaceWindowKind.behavior(kind: kind)
        switch kind {
        case "osd", "toast", "overlay": keyboard = false
        case "popup": keyboard = Self.bool(property("keyboard")) ?? true
        case "window": keyboard = true
        default: keyboard = Self.bool(property("keyboard")) ?? false
        }
        switch property("click-through") {
        case .bool(true): clickThrough = .on
        case .bool(false): clickThrough = .off
        case .string("auto"): clickThrough = .auto
        default: clickThrough = kind == "overlay" ? .on : .off
        }
        switch Self.text(property("fullscreen")) {
        case "hide": hideInFullscreen = true
        case "show": hideInFullscreen = false
        default: hideInFullscreen = kind == "panel"
        }
        overhang = Self.bool(property("overhang")) ?? false
        safeArea = Self.bool(property("safe-area")) ?? true
        reserve = kind == "panel" && (Self.bool(property("reserve")) ?? false)
        let anchor = Self.text(property("anchor")) ?? SurfaceWindowKind.defaultAnchor(kind)
        motion = Self.text(property("motion")) ?? SurfaceWindowKind.defaultMotion(kind, anchor: anchor)
        if kind == "popup" {
            closeOn = Self.triggers(property("close-on")) ?? Self.closeOnDefault
            hoverEdge = Self.bool(property("hover-edge")) ?? false
            hoverMargin = Self.number(property("hover-margin")).map { CGFloat($0) } ?? SurfacePlacement.points(property("hover-margin"))
            hoverGap = Self.number(property("hover-gap")).map { CGFloat($0) } ?? SurfacePlacement.points(property("hover-gap"))
            group = Self.text(property("group"))
        } else {
            closeOn = []
            hoverEdge = false
            hoverMargin = 0
            hoverGap = 0
            group = nil
        }
        timeout = kind == "osd" ? (Self.seconds(property("timeout")) ?? 2) : nil
        title = Self.text(property("title")) ?? ""
        titleVisible = Self.bool(property("title-visible")) ?? true
        titlebar = Self.bool(property("titlebar")) ?? true
        resizable = Self.bool(property("resizable")) ?? true
        closable = Self.bool(property("closable")) ?? true
        miniaturizable = Self.bool(property("miniaturizable")) ?? false
        autosave = Self.text(property("autosave"))
    }

    var animates: Bool { motion != "none" && (kind == "popup" || kind == "osd") }

    var styleMask: NSWindow.StyleMask {
        guard kind == "window" else { return [.borderless, .nonactivatingPanel] }
        var mask: NSWindow.StyleMask = [.titled]
        if closable { mask.insert(.closable) }
        if resizable { mask.insert(.resizable) }
        if miniaturizable { mask.insert(.miniaturizable) }
        if !titlebar { mask.insert(.fullSizeContentView) }
        return mask
    }

    static func text(_ value: Value) -> String? {
        if case .string(let text) = value { return text }
        return nil
    }

    static func bool(_ value: Value) -> Bool? {
        if case .bool(let flag) = value { return flag }
        return nil
    }

    static func number(_ value: Value) -> Double? {
        if case .number(let number) = value, number.isFinite { return number }
        return nil
    }

    static func seconds(_ value: Value) -> Double? {
        if let number = number(value) { return number }
        guard let text = text(value) else { return nil }
        let units: [(String, Double)] = [("ms", 0.001), ("s", 1), ("m", 60)]
        for (suffix, factor) in units where text.hasSuffix(suffix) {
            if let number = Double(text.dropLast(suffix.count)) { return number * factor }
        }
        return nil
    }

    static func triggers(_ value: Value) -> Set<CloseTrigger>? {
        let words: [String]
        switch value {
        case .string(let text): words = text.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        case .list(let items): words = items.compactMap(text)
        default: return nil
        }
        return Set(words.compactMap(CloseTrigger.init(rawValue:)))
    }
}

extension SurfaceWindowKind {
    static func defaultAnchor(_ kind: String) -> String {
        switch kind {
        case "overlay": "fill"
        case "toast": "bottom-right"
        default: "center"
        }
    }

    static func defaultArea(_ kind: String) -> String {
        kind == "overlay" ? "full" : "below-menubar"
    }

    static func defaultMotion(_ kind: String, anchor: String) -> String {
        switch kind {
        case "popup": anchor == "center" || anchor == "fill" ? "fade" : "slide"
        case "osd": "slide"
        default: "none"
        }
    }
}
