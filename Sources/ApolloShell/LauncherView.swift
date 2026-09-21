import ApolloShellCore
import SwiftUI

/// Search field at the top, the scrollable app list below. The glass
/// background comes from the surrounding NSGlassEffectView (see LauncherController).
struct LauncherView: View {
    @Bindable var model: LauncherModel
    @FocusState private var searchFocused: Bool
    @Environment(\.shellStyle) private var style

    var body: some View {
        VStack(spacing: 0) {
            searchField
            // With a theme: `--apollo-separator-color` and `--apollo-text-color`.
            if let separator = style.color(.separator) {
                Rectangle().fill(separator).frame(height: 1)
            } else {
                Divider().opacity(0.4)
            }
            if model.results.isEmpty {
                Text(model.query.trimmingCharacters(in: .whitespaces).hasPrefix(LauncherQuery.actionPrefix) ? "No Match" : "No App Found")
                    .foregroundStyle(style.paint(.secondaryText, or: .secondary))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .foregroundStyle(style.paint(.text, or: .primary))
        // Able to start typing right away on every open.
        .onChange(of: model.openCount, initial: true) { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            ThemedIcon("bar-launcher")
                .font(style.font(size: 18, weight: .medium))
                .frame(width: 20, height: 20)
                .foregroundStyle(style.paint(.secondaryText, or: .secondary))
            TextField("Search…", text: $model.query)
                .textFieldStyle(.plain)
                .font(style.font(size: 20))
                .focused($searchFocused)
                .onSubmit { model.launchSelected() }
                .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                .onExitCommand { model.onClose() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, row in
                        LauncherRowView(row: row, model: model, selected: index == model.selectedIndex)
                            .id(row.id)
                            .onTapGesture {
                                model.selectedIndex = index
                                model.launchSelected()
                            }
                            .modifier(AppRowExtras(model: model, app: row.app) {
                                model.selectedIndex = index
                            })
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selectedIndex) { _, index in
                guard model.results.indices.contains(index) else { return }
                proxy.scrollTo(model.results[index].id)
            }
        }
    }
}

/// What only app rows have: the right-click menu (the app's own, out of
/// Apple's Dock - it needs a moment, hence AppKit instead of `contextMenu`)
/// and dragging within the pinned block.
private struct AppRowExtras: ViewModifier {
    let model: LauncherModel
    let app: AppEntry?
    let select: () -> Void

    func body(content: Content) -> some View {
        if let app {
            content
                .overlay {
                    RightClickCatcher { view in
                        select()
                        model.onRightClick(app, view)
                    }
                }
                .modifier(PinDragging(model: model, app: app))
        } else {
            content
        }
    }
}

/// Pinned rows can be dragged within the pinned block (the bundle ID as
/// text); every other row neither drags nor takes a drop.
private struct PinDragging: ViewModifier {
    let model: LauncherModel
    let app: AppEntry

    func body(content: Content) -> some View {
        if model.canDragPin(app), let id = app.bundleID {
            content
                .draggable(id)
                .dropDestination(for: String.self) { items, _ in
                    // Only a pin of this list; text dragged in from elsewhere
                    // is not ours.
                    guard let moved = items.first, moved != id, model.pinned.contains(moved) else { return false }
                    model.onMovePin(moved, id)
                    return true
                }
        } else {
            content
        }
    }
}

/// One row: an icon (app icon, wallpaper preview or symbol), a title,
/// for actions a grey line below, and on the right what Return does.
private struct LauncherRowView: View {
    let row: LauncherRow
    let model: LauncherModel
    let selected: Bool

    @Environment(\.shellStyle) private var style

    var body: some View {
        let radius = style.controlRadius(10)
        HStack(spacing: 12) {
            icon
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(style.font(size: 15))
                    .lineLimit(1)
                    .foregroundStyle(style.paint(.text, or: .primary))
                if let subtitle {
                    Text(subtitle)
                        .font(style.font(size: 12))
                        .lineLimit(1)
                        .foregroundStyle(armed ? AnyShapeStyle(Color.red) : style.paint(.secondaryText, or: .secondary))
                }
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(style.font(size: 11, weight: .medium))
                    .foregroundStyle(style.paint(.secondaryText, or: .secondary))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // With a theme, `--apollo-launcher-row-height` sets the row height;
        // without a theme, the content determines it as before.
        .frame(minHeight: style.length(.launcherRowHeight))
        .background {
            // With a theme, `--apollo-launcher-highlight-color` colors the
            // selected row (or the gradient next to it).
            if selected {
                if style.paintsLauncherHighlight {
                    RoundedRectangle(cornerRadius: radius).fill(style.launcherHighlightFill)
                } else {
                    RoundedRectangle(cornerRadius: radius).fill(Color.primary.opacity(0.12))
                }
            }
        }
        .contentShape(.rect)
    }
}

private extension LauncherRowView {
    var armed: Bool {
        if case .action(let action) = row { return model.armed == action }
        return false
    }

    @ViewBuilder var icon: some View {
        switch row {
        case .app(let app):
            Image(nsImage: model.icon(for: app)).resizable()
        case .wallpaper(let wallpaper):
            if let image = model.thumbnail(for: wallpaper) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    // Square like the app icons, whatever the picture's shape.
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                symbol("photo")
            }
        case .action(let action): symbol(action.symbol)
        case .calculation: symbol("equal")
        case .theme(_, _, let current): symbol(current ? "checkmark.circle.fill" : "paintpalette")
        case .note: symbol("info.circle")
        }
    }

    func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(style.font(size: 17, weight: .medium))
            .foregroundStyle(style.paint(.secondaryText, or: .secondary))
    }

    var title: String {
        switch row {
        case .app(let app): app.name
        case .action(let action): action.title
        case .calculation(let result): result
        case .theme(_, let title, _): title
        case .wallpaper(let wallpaper): wallpaper.name
        case .note(let text): text
        }
    }

    var subtitle: String? {
        switch row {
        case .action(let action):
            if armed { return String(localized: "Press Return again to \(action.title.lowercased())") }
            return action.subtitle
        case .calculation: return String(localized: "Return copies the result")
        case .wallpaper(let wallpaper) where !wallpaper.isAvailable:
            return String(localized: "Not downloaded – Return opens Wallpaper settings")
        default: return nil
        }
    }

    var trailing: String? {
        switch row {
        case .action(let action) where action.completion != nil: ">\(action.completion!)"
        case .theme(_, _, true): String(localized: "Current")
        default: nil
        }
    }
}
