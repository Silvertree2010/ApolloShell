import AppKit
import SwiftUI
import ApolloConfig
import ApolloStyle

struct SurfacePlacement: Equatable {
    enum Anchor: String {
        case top, bottom, left, right, center, fill
        case topLeft = "top-left"
        case topRight = "top-right"
        case bottomLeft = "bottom-left"
        case bottomRight = "bottom-right"
    }

    enum Area: String {
        case full
        case belowMenubar = "below-menubar"
        case visible
    }

    var anchor: Anchor = .center
    var area: Area = .belowMenubar
    var width: CSSLength?
    var height: CSSLength?
    var margin = EdgeInsets()
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0

    init(anchor: Anchor = .center, area: Area = .belowMenubar, width: CSSLength? = nil, height: CSSLength? = nil,
         margin: EdgeInsets = EdgeInsets(), offsetX: CGFloat = 0, offsetY: CGFloat = 0) {
        self.anchor = anchor
        self.area = area
        self.width = width
        self.height = height
        self.margin = margin
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    init(property: (String) -> Value, style: ComputedStyle) {
        if case .string(let name) = property("anchor"), let anchor = Anchor(rawValue: name) { self.anchor = anchor }
        if case .string(let name) = property("area"), let area = Area(rawValue: name) { self.area = area }
        width = StyleValues.length(style["width"])
        height = StyleValues.length(style["height"])
        margin = StyleValues.sides(style["margin"])
        offsetX = Self.points(property("offset-x"))
        offsetY = Self.points(property("offset-y"))
    }

    static func points(_ value: Value) -> CGFloat {
        switch value {
        case .number(let number): return CGFloat(number)
        case .string(let text):
            let trimmed = text.hasSuffix("px") ? String(text.dropLast(2)) : text
            return Double(trimmed).map { CGFloat($0) } ?? 0
        default: return 0
        }
    }

    static func areaRect(_ area: Area, frame: CGRect, visible: CGRect) -> CGRect {
        switch area {
        case .full: frame
        case .visible: visible
        case .belowMenubar: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: visible.maxY - frame.minY)
        }
    }

    func frame(screen: CGRect, visible: CGRect, fitting: CGSize) -> CGRect {
        let bounds = Self.areaRect(area, frame: screen, visible: visible)
        let inner = CGRect(
            x: bounds.minX + margin.leading,
            y: bounds.minY + margin.bottom,
            width: max(0, bounds.width - margin.leading - margin.trailing),
            height: max(0, bounds.height - margin.top - margin.bottom)
        )
        if anchor == .fill { return inner.integral }
        let size = CGSize(
            width: Self.resolve(width, against: bounds.width) ?? fitting.width,
            height: Self.resolve(height, against: bounds.height) ?? fitting.height
        )
        let x: CGFloat
        switch anchor {
        case .left, .topLeft, .bottomLeft: x = inner.minX + offsetX
        case .right, .topRight, .bottomRight: x = inner.maxX - size.width - offsetX
        default: x = inner.midX - size.width / 2 + offsetX
        }
        let y: CGFloat
        switch anchor {
        case .top, .topLeft, .topRight: y = inner.maxY - size.height - offsetY
        case .bottom, .bottomLeft, .bottomRight: y = inner.minY + offsetY
        default: y = inner.midY - size.height / 2 - offsetY
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height).integral
    }

    static func resolve(_ length: CSSLength?, against extent: CGFloat) -> CGFloat? {
        guard let length else { return nil }
        switch length.unit {
        case .points: return CGFloat(length.value)
        case .percent: return extent * CGFloat(length.value) / 100
        default: return nil
        }
    }
}

enum SurfaceWindowKind {
    static func level(_ layer: String?, kind: String) -> NSWindow.Level {
        switch layer ?? defaultLayer(kind) {
        case "desktop": NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case "normal": .normal
        case "status": .statusBar
        case "popup": .popUpMenu
        case "overlay": NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
        default: .floating
        }
    }

    static func defaultLayer(_ kind: String) -> String {
        switch kind {
        case "popup", "toast", "osd": "popup"
        case "overlay": "overlay"
        case "window": "normal"
        default: "floating"
        }
    }

    static func behavior(kind: String) -> NSWindow.CollectionBehavior {
        switch kind {
        case "popup", "osd": [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        case "toast": [.canJoinAllSpaces, .transient, .ignoresCycle]
        case "window": [.moveToActiveSpace]
        default: [.canJoinAllSpaces, .stationary, .ignoresCycle]
        }
    }
}
