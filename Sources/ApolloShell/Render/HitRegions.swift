import SwiftUI
import ApolloConfig
import ApolloStyle

struct HitRegion: Equatable {
    var identity: Identity
    var frame: CGRect
}

@MainActor
final class HitRegions {
    private var regions: [String: [HitRegion]] = [:]
    var onChange: @MainActor (String) -> Void = { _ in }

    func regions(for surfaceKey: String) -> [HitRegion] {
        regions[surfaceKey] ?? []
    }

    func contains(_ point: CGPoint, surfaceKey: String) -> Bool {
        regions(for: surfaceKey).contains { $0.frame.contains(point) }
    }

    func update(_ list: [HitRegion], surfaceKey: String) {
        guard regions[surfaceKey] != list else { return }
        regions[surfaceKey] = list
        onChange(surfaceKey)
    }

    func remove(_ surfaceKey: String) {
        regions[surfaceKey] = nil
    }
}

struct HitRegionEntry {
    var identity: Identity
    var anchor: Anchor<CGRect>
}

struct HitRegionKey: PreferenceKey {
    static let defaultValue: [HitRegionEntry] = []

    static func reduce(value: inout [HitRegionEntry], nextValue: () -> [HitRegionEntry]) {
        value += nextValue()
    }
}

struct HitRegionMarker: ViewModifier {
    let active: Bool
    let identity: Identity

    func body(content: Content) -> some View {
        if active {
            content.anchorPreference(key: HitRegionKey.self, value: .bounds) { [HitRegionEntry(identity: identity, anchor: $0)] }
        } else {
            content
        }
    }
}

struct HitRegionCollector: ViewModifier {
    let surfaceKey: String
    let regions: HitRegions

    func body(content: Content) -> some View {
        content.backgroundPreferenceValue(HitRegionKey.self) { entries in
            GeometryReader { proxy in
                let list = entries.map { HitRegion(identity: $0.identity, frame: proxy[$0.anchor]) }
                Color.clear
                    .onAppear { regions.update(list, surfaceKey: surfaceKey) }
                    .onChange(of: list) { _, new in regions.update(new, surfaceKey: surfaceKey) }
            }
        }
    }
}

extension StyleValues {
    static func visibleBackground(_ style: ComputedStyle) -> Bool {
        var layers: [BackgroundLayer] = []
        if case .layers(let list)? = style["background"] { layers = list }
        if case .color(let color)? = style["background-color"] { layers.append(.color(color)) }
        if (number(style["opacity"]) ?? 1) <= 0 { return false }
        return layers.contains { layer in
            if case .color(let color) = layer { return !color.isTransparent }
            return true
        }
    }
}

extension CSSColor {
    var isTransparent: Bool {
        switch self {
        case .rgba(_, _, _, let alpha), .system(_, let alpha): alpha <= 0
        case .currentColor: false
        }
    }
}
