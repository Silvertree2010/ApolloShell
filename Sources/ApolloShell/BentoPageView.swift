import ApolloShellCore
import SwiftUI

/// Eine Seite: jedes Widget an seinem Rahmen (Referenzpunkte). Gesetzt
/// ueber Rahmen und Versatz in ganzen Punkten statt ueber ein eigenes
/// `Layout` - siehe den Kommentar ueber `DashboardGrid`: ein eigenes Layout
/// rundete innen anders und verschob Text um einen Pixel.
struct BentoPageView: View {
    let page: DashboardPage
    let context: WidgetContext

    var body: some View {
        if page.widgets.isEmpty {
            BentoEmptyPage()
        } else {
            ZStack(alignment: .topLeading) {
                ForEach(page.widgets) { widget in
                    WidgetView(widget: widget, context: context)
                        .frame(width: widget.frame.width, height: widget.frame.height)
                        .offset(x: widget.frame.x, y: widget.frame.y)
                }
            }
            .frame(width: CGFloat(DashboardGeometry.width), height: CGFloat(DashboardGeometry.height),
                   alignment: .topLeading)
        }
    }
}

/// Eine Seite ohne Widgets: ein ruhiger Hinweis statt einer leeren Flaeche.
struct BentoEmptyPage: View {
    @Environment(\.shellStyle) private var style

    var body: some View {
        Card(radius: 28) {
            VStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(style.font(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Leere Seite")
                    .font(style.font(size: 15, weight: .semibold))
                Text("In Nexus bearbeiten")
                    .font(style.font(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
