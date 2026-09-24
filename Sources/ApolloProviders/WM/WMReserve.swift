import Foundation

public struct PanelReserve: Sendable, Equatable {
    public enum Edge: String, Sendable, CaseIterable {
        case top, left, bottom, right
    }

    public var screen: String
    public var edge: Edge
    public var size: Double

    public init(screen: String, edge: Edge, size: Double) {
        self.screen = screen
        self.edge = edge
        self.size = size
    }
}

public enum WMReserve {
    public static func insets(panels: [PanelReserve], settings: WMSettings, screens: [WMScreen]) -> [String: WMInsets] {
        var result: [String: WMInsets] = [:]
        for screen in screens {
            result[screen.key] = .zero
        }
        if settings.reservePanels {
            for panel in panels where result[panel.screen] != nil && panel.size.isFinite && panel.size > 0 {
                var add = WMInsets.zero
                switch panel.edge {
                case .top: add.top = panel.size
                case .left: add.left = panel.size
                case .bottom: add.bottom = panel.size
                case .right: add.right = panel.size
                }
                result[panel.screen] = result[panel.screen, default: .zero] + add
            }
        }
        for reserve in settings.reserves {
            let add = WMInsets(top: reserve.top, left: reserve.left, bottom: reserve.bottom, right: reserve.right)
            for key in targets(reserve.screen, screens: screens) {
                result[key] = result[key, default: .zero] + add
            }
        }
        return result
    }

    static func targets(_ screen: String?, screens: [WMScreen]) -> [String] {
        let main = screens.first(where: \.isMain) ?? screens.first
        switch screen {
        case nil, "all": return screens.map(\.key)
        case "main", "pointer": return main.map { [$0.key] } ?? []
        case let key?:
            if screens.contains(where: { $0.key == key }) { return [key] }
            return main.map { [$0.key] } ?? []
        }
    }
}
