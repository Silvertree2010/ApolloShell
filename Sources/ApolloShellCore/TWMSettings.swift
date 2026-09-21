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

    public static let focusDelayRange = 0...500
    public static let gapRange = 0.0...40.0
    public static let glideRange = 0.1...0.8

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
        focusDelayMilliseconds = min(max(focusDelayMilliseconds, Self.focusDelayRange.lowerBound), Self.focusDelayRange.upperBound)
        innerGap = min(max(innerGap, Self.gapRange.lowerBound), Self.gapRange.upperBound)
        outerGap = min(max(outerGap, Self.gapRange.lowerBound), Self.gapRange.upperBound)
        glideDuration = min(max(glideDuration, Self.glideRange.lowerBound), Self.glideRange.upperBound)
    }
}
