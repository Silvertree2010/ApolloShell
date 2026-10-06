import SwiftUI
import ApolloStyle

enum SurfaceBleed {
    static let glass: CGFloat = 32

    static func insets(_ style: ComputedStyle, glass g: Bool = true) -> EdgeInsets {
        var r = EdgeInsets()
        if case .shadows(let list)? = style["box-shadow"] {
            for s in list {
                let e = CGFloat(s.blur + max(0, s.spread))
                r = union(r, EdgeInsets(top: max(0, e - CGFloat(s.y)), leading: max(0, e - CGFloat(s.x)),
                                        bottom: max(0, e + CGFloat(s.y)), trailing: max(0, e + CGFloat(s.x))))
            }
        }
        if g, case .layers(let list)? = style["background"], list.contains(where: { if case .glass = $0 { true } else { false } }) {
            r = union(r, EdgeInsets(top: glass, leading: glass, bottom: glass, trailing: glass))
        }
        return EdgeInsets(top: r.top.rounded(.up), leading: r.leading.rounded(.up), bottom: r.bottom.rounded(.up), trailing: r.trailing.rounded(.up))
    }

    static func union(_ a: EdgeInsets, _ b: EdgeInsets) -> EdgeInsets {
        EdgeInsets(top: max(a.top, b.top), leading: max(a.leading, b.leading), bottom: max(a.bottom, b.bottom), trailing: max(a.trailing, b.trailing))
    }

    static func clamp(_ b: EdgeInsets, frame: CGRect, screen: CGRect) -> EdgeInsets {
        EdgeInsets(top: max(0, min(b.top, screen.maxY - frame.maxY)), leading: max(0, min(b.leading, frame.minX - screen.minX)),
                   bottom: max(0, min(b.bottom, frame.minY - screen.minY)), trailing: max(0, min(b.trailing, screen.maxX - frame.maxX)))
    }
}
