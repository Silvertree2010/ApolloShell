import Foundation

// What `BarPreset`, `UtilitiesPreset` and `DashboardPreset` have in common: a
// fixed list of finished levels, each with a title, a summary and the level it
// creates - plus a default that "Reset" leads to. Nexus builds the prompt
// before the replacement on it (see NexusPresetControls in the app target);
// the three template enums themselves stay where they are (with their level),
// only their conformance stands here beside them.

/// One template for a level (the bar, the panel or the dashboard): the title
/// and the summary for the menu and the prompt, `layout` the finished level.
public protocol LayoutPreset: CaseIterable, Identifiable, Sendable where AllCases: RandomAccessCollection {
    associatedtype Layout: Equatable, Sendable

    var title: String { get }
    var summary: String { get }
    var layout: Layout { get }

    /// What "Reset" leads to - with all three the first template, called
    /// "Caelestia" or "Standard".
    static var `default`: Self { get }
}

/// What a prompt in Nexus replaces in the end: a chosen template or the
/// default. The texts of the prompt stay with the editors, because their
/// wording differs (bar/panel/dashboard) - only what the two cases have in
/// common is here.
public enum LayoutPresetReplacement<P: LayoutPreset> {
    case preset(P)
    case reset

    public var layout: P.Layout {
        switch self {
        case .preset(let preset): preset.layout
        case .reset: P.default.layout
        }
    }

    /// The label of the confirm button - the same with all three.
    public var confirmLabel: String {
        switch self {
        case .preset: String(localized: "Load")
        case .reset: String(localized: "Reset")
        }
    }
}
