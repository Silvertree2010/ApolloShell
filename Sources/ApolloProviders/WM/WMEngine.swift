import Foundation
import ApolloWMCore

public struct WMInsets: Sendable, Equatable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = WMInsets()

    public static func + (lhs: WMInsets, rhs: WMInsets) -> WMInsets {
        WMInsets(top: lhs.top + rhs.top, left: lhs.left + rhs.left, bottom: lhs.bottom + rhs.bottom, right: lhs.right + rhs.right)
    }
}

public struct WMScreen: Sendable, Equatable {
    public var key: String
    public var isMain: Bool

    public init(key: String, isMain: Bool) {
        self.key = key
        self.isMain = isMain
    }
}

public struct WMWindowInfo: Sendable, Equatable {
    public var id: UInt32
    public var pid: Int32
    public var app: String
    public var bundleID: String?
    public var title: String
    public var floating: Bool
    public var scratchpad: Bool
    public var fullscreen: Bool
    public var desktop: Int?
    public var display: Int?
    public var workspace: Int?
    public var group: [UInt32]
    public var frame: CGRect?

    public init(id: UInt32, pid: Int32 = 0, app: String = "", bundleID: String? = nil, title: String = "", floating: Bool = false, scratchpad: Bool = false, fullscreen: Bool = false, desktop: Int? = nil, display: Int? = nil, workspace: Int? = nil, group: [UInt32] = [], frame: CGRect? = nil) {
        self.id = id
        self.pid = pid
        self.app = app
        self.bundleID = bundleID
        self.title = title
        self.floating = floating
        self.scratchpad = scratchpad
        self.fullscreen = fullscreen
        self.desktop = desktop
        self.display = display
        self.workspace = workspace
        self.group = group
        self.frame = frame
    }
}

public struct WMTabInfo: Sendable, Equatable {
    public var window: UInt32
    public var title: String
    public var app: String

    public init(window: UInt32, title: String, app: String) {
        self.window = window
        self.title = title
        self.app = app
    }
}

public struct WMTabBarInfo: Sendable, Equatable {
    public var frame: CGRect
    public var screen: String
    public var active: UInt32
    public var tabs: [WMTabInfo]

    public init(frame: CGRect, screen: String, active: UInt32, tabs: [WMTabInfo]) {
        self.frame = frame
        self.screen = screen
        self.active = active
        self.tabs = tabs
    }
}

public struct WMState: Sendable, Equatable {
    public var layout: WMSettings.Layout
    public var windows: [WMWindowInfo]
    public var focused: UInt32?
    public var desktop: Int
    public var workspace: Int
    public var tabBars: [WMTabBarInfo]

    public init(layout: WMSettings.Layout = .dwindle, windows: [WMWindowInfo] = [], focused: UInt32? = nil, desktop: Int = 1, workspace: Int = 1, tabBars: [WMTabBarInfo] = []) {
        self.layout = layout
        self.windows = windows
        self.focused = focused
        self.desktop = desktop
        self.workspace = workspace
        self.tabBars = tabBars
    }
}

@MainActor
public protocol WMEngine: AnyObject {
    var accessibilityTrusted: Bool { get }
    var screenRecordingAllowed: Bool { get }
    var screens: [WMScreen] { get }
    var onChange: (@MainActor () -> Void)? { get set }
    func start(_ settings: WMSettings) -> Bool
    func configure(_ settings: WMSettings)
    func stop()
    func perform(_ command: Command)
    func setLayout(_ layout: WMSettings.Layout)
    func focusWindow(_ id: UInt32) -> Bool
    func setReserved(_ insets: [String: WMInsets])
    func state() -> WMState
}
