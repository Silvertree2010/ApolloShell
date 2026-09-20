import ApolloShellCore
import SwiftUI

/// One page: every widget at its frame (reference points). Set through frames
/// and offsets in whole points instead of through a `Layout` of its own - see
/// the comment above `DashboardGrid`: a layout of its own rounded differently
/// inside and shifted text by a pixel.
///
/// When `editor` is editing this page right now (`editor.isEditing`), it draws
/// the editing surface out of `BentoEditOverlay.swift` instead of the quiet
/// view: wobbling, selectable widgets with a remove and a size handle, and a
/// target for widgets dragged out of Nexus. When not editing, the tree stays
/// exactly as it was before the editing (which matters for the image
/// comparison, see design/2026-09-18-bento-plan-edit.md).
struct BentoPageView: View {
    let page: DashboardPage
    let context: WidgetContext
    let editor: DashboardEditor
    @Environment(\.shellStyle) private var style
    @Environment(\.dashboardRendersForScreenshot) private var rendersForScreenshot

    /// A named coordinate space for dragging and resizing (`BentoEditOverlay`):
    /// the page itself does not grow during a drag (unlike the frame of a
    /// single widget), so drag points in it stay stable.
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
            #if DEBUG
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { editor.debugPageRectInHost = geometry.frame(in: .named(DashboardView.rootSpace)) }
                        .onChange(of: geometry.frame(in: .named(DashboardView.rootSpace))) { _, rect in editor.debugPageRectInHost = rect }
                }
            }
            #endif
            // `ImageRenderer` (image samples) does not draw the AppKit-backed
            // drop target offscreen (a red no-entry sign instead of the page,
            // measured 18.09.) - so it stays out in `RenderMode`; the real
            // dashboard always keeps it.
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

    /// The preview while dragging out of Nexus: a dashed outline, red when it
    /// does not fit there.
    @ViewBuilder
    private func dropGhost(_ preview: (frame: WidgetFrame, valid: Bool)) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(preview.valid ? style.accent : Color.red, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: preview.frame.width, height: preview.frame.height)
            .padding(.leading, preview.frame.x)
            .padding(.top, preview.frame.y)
            .allowsHitTesting(false)
    }
}

/// A page without widgets: a quiet note instead of an empty area.
struct BentoEmptyPage: View {
    @Environment(\.shellStyle) private var style

    var body: some View {
        Card(radius: 28) {
            VStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(style.font(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Empty page")
                    .font(style.font(size: 15, weight: .semibold))
                Text("Nexus › Edit Interface")
                    .font(style.font(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
