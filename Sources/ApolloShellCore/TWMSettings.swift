/// The tiling window manager (Nexus > TWM). Off by default: it rearranges
/// every window, so a user turns it on knowingly.
public struct TWMSettings: Codable, Equatable, Sendable {
    /// How window sizes animate, see ApolloWM's ResizeAnimation.
    public enum Resize: String, Codable, CaseIterable, Sendable {
        /// A snapshot glides for apps too slow to resize every frame.
        case proxy
        /// The size glides along for every app.
        case smooth
        /// Only the position glides; the size jumps once.
        case snap
    }

    public var enabled = false
    public var focusFollowsMouse = true
    /// How long the mouse rests over a window before it is focused.
    public var focusDelayMilliseconds = 25
    public var innerGap = 10.0
    public var outerGap = 12.0
    /// Roughly how long a glide takes, in seconds.
    public var glideDuration = 0.28
    public var resize = Resize.proxy
    /// The frame around the focused window, in points; 0 hides it.
    public var borderWidth = 2.0
    /// Its corner radius, to match the windows' own corners.
    public var borderRadius = 16.0
    /// Room above a tab group's window for its tab bar.
    public var tabBarHeight = 30.0
    /// How much Super + R and one arrow change a window, as a share of the screen.
    public var resizeStep = 0.03
    /// How long a key mode (Super + R, Super + M) waits for the next key.
    public var modeTimeout = 6.0
    /// How much of the screen the scratchpad window covers.
    public var scratchpadShare = 0.7
    /// Super + 1-9 shows Apple's desktops. Off: the TWM's own workspaces,
    /// whose windows wait past the screen edge.
    public var appleDesktops = true
    /// Bundle id for Super + T; empty means the first one installed of
    /// kitty, Ghostty, Terminal.
    public var terminal = ""
    /// Super + Q on an app's last window quits the app (the Finder never).
    public var quitWithLastWindow = true

    public static let focusDelayRange = 0...500
    public static let gapRange = 0.0...40.0
    public static let glideRange = 0.1...0.8
    public static let borderWidthRange = 0.0...6.0
    public static let borderRadiusRange = 0.0...30.0
    public static let tabBarRange = 18.0...48.0
    public static let resizeStepRange = 0.01...0.15
    public static let modeTimeoutRange = 2.0...20.0
    public static let scratchpadRange = 0.4...0.95

    public init() {}

    /// The focus delay as a Double, for a slider bound by key path (a
    /// hand-made Binding with closures crashed: SwiftUI read it off the
    /// main actor).
    public var focusDelay: Double {
        get { Double(focusDelayMilliseconds) }
        set { focusDelayMilliseconds = Int(newValue.rounded()) }
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.enabled, into: &enabled)
        c.lenient(.focusFollowsMouse, into: &focusFollowsMouse)
        c.lenient(.focusDelayMilliseconds, into: &focusDelayMilliseconds)
        c.lenient(.innerGap, into: &innerGap)
        c.lenient(.outerGap, into: &outerGap)
        c.lenient(.glideDuration, into: &glideDuration)
        c.lenient(.resize, into: &resize)
        c.lenient(.borderWidth, into: &borderWidth)
        c.lenient(.borderRadius, into: &borderRadius)
        c.lenient(.tabBarHeight, into: &tabBarHeight)
        c.lenient(.resizeStep, into: &resizeStep)
        c.lenient(.modeTimeout, into: &modeTimeout)
        c.lenient(.scratchpadShare, into: &scratchpadShare)
        c.lenient(.appleDesktops, into: &appleDesktops)
        c.lenient(.terminal, into: &terminal)
        c.lenient(.quitWithLastWindow, into: &quitWithLastWindow)
        focusDelayMilliseconds = min(max(focusDelayMilliseconds, Self.focusDelayRange.lowerBound), Self.focusDelayRange.upperBound)
        innerGap = min(max(innerGap, Self.gapRange.lowerBound), Self.gapRange.upperBound)
        outerGap = min(max(outerGap, Self.gapRange.lowerBound), Self.gapRange.upperBound)
        glideDuration = min(max(glideDuration, Self.glideRange.lowerBound), Self.glideRange.upperBound)
        borderWidth = min(max(borderWidth, Self.borderWidthRange.lowerBound), Self.borderWidthRange.upperBound)
        borderRadius = min(max(borderRadius, Self.borderRadiusRange.lowerBound), Self.borderRadiusRange.upperBound)
        tabBarHeight = min(max(tabBarHeight, Self.tabBarRange.lowerBound), Self.tabBarRange.upperBound)
        resizeStep = min(max(resizeStep, Self.resizeStepRange.lowerBound), Self.resizeStepRange.upperBound)
        modeTimeout = min(max(modeTimeout, Self.modeTimeoutRange.lowerBound), Self.modeTimeoutRange.upperBound)
        scratchpadShare = min(max(scratchpadShare, Self.scratchpadRange.lowerBound), Self.scratchpadRange.upperBound)
    }
}
