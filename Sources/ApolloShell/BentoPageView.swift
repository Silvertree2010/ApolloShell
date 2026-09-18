import ApolloShellCore
import SwiftUI

/// Eine Seite: jedes Widget an seinem Rahmen (Referenzpunkte). Gesetzt
/// ueber Rahmen und Versatz in ganzen Punkten statt ueber ein eigenes
/// `Layout` - siehe den Kommentar ueber `DashboardGrid`: ein eigenes Layout
/// rundete innen anders und verschob Text um einen Pixel.
///
/// Bearbeitet `editor` gerade diese Seite (`editor.isEditing`), zeichnet sie
/// statt der ruhigen Ansicht die Bearbeitungs-Oberflaeche aus
/// `BentoEditOverlay.swift`: wackelnde, waehlbare Widgets mit Entfernen- und
/// Groessen-Griff, und ein Ziel fuer Widgets, die aus Nexus gezogen werden.
/// Nicht editierend bleibt der Baum genau wie vor der Bearbeitung (wichtig
/// fuer den Bildvergleich, siehe design/2026-09-18-bento-plan-edit.md).
struct BentoPageView: View {
    let page: DashboardPage
    let context: WidgetContext
    let editor: DashboardEditor
    @Environment(\.shellStyle) private var style
    @Environment(\.dashboardRendersForScreenshot) private var rendersForScreenshot

    /// Benanntern Bezugsraum fuer Ziehen/Groesse-aendern (`BentoEditOverlay`):
    /// die Seite selbst waechst waehrend eines Zugs nicht mit (anders als der
    /// Rahmen eines einzelnen Widgets), also bleiben Ziehpunkte darin stabil.
    static let coordinateSpaceName = "bentoPage"

    var body: some View {
        if editor.isEditing {
            ZStack(alignment: .topLeading) {
                ForEach(page.widgets) { widget in
                    EditableWidgetView(widget: widget, context: context, editor: editor)
                }
                if let preview = editor.dropPreview {
                    dropGhost(preview)
                }
            }
            .frame(width: CGFloat(DashboardGeometry.width), height: CGFloat(DashboardGeometry.height),
                   alignment: .topLeading)
            .coordinateSpace(name: Self.coordinateSpaceName)
            .contentShape(Rectangle())
            // `ImageRenderer` (Bildproben) zeichnet das AppKit-hinterlegte
            // Ablegeziel offscreen nicht (rotes Verbotszeichen statt der
            // Seite, gemessen 18.09.) - in `RenderMode` bleibt es darum weg;
            // das echte Dashboard behaelt es immer.
            .modifier(BentoDropTarget(editor: editor, active: !rendersForScreenshot))
        } else if page.widgets.isEmpty {
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

    /// Vorschau beim Ziehen aus Nexus: gestrichelter Umriss, rot wenn er dort
    /// nicht passt.
    @ViewBuilder
    private func dropGhost(_ preview: (frame: WidgetFrame, valid: Bool)) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(preview.valid ? style.accent : Color.red, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: preview.frame.width, height: preview.frame.height)
            .offset(x: preview.frame.x, y: preview.frame.y)
            .allowsHitTesting(false)
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
