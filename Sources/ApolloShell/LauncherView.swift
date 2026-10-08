import ApolloShellCore
import SwiftUI

/// Suchfeld oben, darunter die scrollbare App-Liste. Der Glas-Hintergrund
/// kommt vom NSGlassEffectView drumherum (siehe LauncherController).
struct LauncherView: View {
    @Bindable var model: LauncherModel
    @FocusState private var searchFocused: Bool
    @Environment(\.shellStyle) private var style

    var body: some View {
        VStack(spacing: 0) {
            searchField
            // Mit Theme: `--apollo-separator-color` und `--apollo-text-color`.
            if let separator = style.color(.separator) {
                Rectangle().fill(separator).frame(height: 1)
            } else {
                Divider().opacity(0.4)
            }
            if model.results.isEmpty {
                Text("Nothing Found")
                    .foregroundStyle(style.paint(.secondaryText, or: .secondary))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .foregroundStyle(style.paint(.text, or: .primary))
        // Bei jedem Oeffnen sofort lostippen koennen.
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
                    // `@Sendable`: SwiftUI 26 legt die Zeilen eines faulen
                    // Stapels auf einem Hintergrund-Thread an und ruft diese
                    // Closure dort auf. Als Main-Actor-Closure schlug sie in
                    // Swifts Isolationspruefung an (EXC_BREAKPOINT in
                    // LauncherView.list); alles mit Main-Actor steckt jetzt in
                    // `LauncherListRow`.
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { @Sendable index, item in
                        LauncherListRow(model: model, index: index, item: item)
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

private struct LauncherListRow: View {
    let model: LauncherModel
    let index: Int
    let item: LauncherItem

    var body: some View {
        ItemRow(model: model, item: item, selected: index == model.selectedIndex)
            .id(item.id)
            .onTapGesture {
                guard item.selectable else { return }
                model.selectedIndex = index
                model.launchSelected()
            }
            .overlay {
                if case .app(let app) = item {
                    RightClickCatcher { view in
                        model.selectedIndex = index
                        model.onRightClick(app, view)
                    }
                }
            }
    }
}

private struct ItemRow: View {
    let model: LauncherModel
    let item: LauncherItem
    let selected: Bool

    @Environment(\.shellStyle) private var style

    var body: some View {
        let radius = style.controlRadius(10)
        HStack(spacing: 12) {
            icon
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(style.font(size: big ? 20 : 15, weight: big ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(style.paint(.text, or: .primary))
                if let sub {
                    Text(sub)
                        .font(style.font(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(style.paint(.secondaryText, or: .secondary))
                }
            }
            Spacer(minLength: 0)
            if let trail {
                Text(trail)
                    .font(style.font(size: 11))
                    .foregroundStyle(style.paint(.secondaryText, or: .secondary))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: style.length(.launcherRowHeight))
        .opacity(item.selectable ? 1 : 0.7)
        .background {
            if selected && item.selectable {
                if style.paintsLauncherHighlight {
                    RoundedRectangle(cornerRadius: radius).fill(style.launcherHighlightFill)
                } else {
                    RoundedRectangle(cornerRadius: radius).fill(Color.primary.opacity(0.12))
                }
            }
        }
        .contentShape(.rect)
    }

    private var big: Bool { if case .calc = item { true } else { false } }

    @ViewBuilder private var icon: some View {
        switch item {
        case .app(let a): Image(nsImage: model.icon(for: a)).resizable()
        case .file(let u): Image(nsImage: model.icon(u)).resizable()
        case .calc: sym("equal")
        case .action(let a): sym(a.symbol)
        case .clip: sym("doc.on.clipboard")
        case .hint: sym("lightbulb")
        }
    }

    private func sym(_ n: String) -> some View {
        Image(systemName: n)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(style.paint(.secondaryText, or: .secondary))
            .frame(width: 32, height: 32)
            .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 8))
    }

    private var title: String {
        switch item {
        case .app(let a): a.name
        case .file(let u): FileManager.default.displayName(atPath: u.path)
        case .calc(_, let v): v
        case .action(let a): a.title
        case .clip(let c): c.text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
        case .hint(let t, _): t
        }
    }

    private var sub: String? {
        switch item {
        case .file(let u): (u.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        case .calc(let e, _): e + "  ·  " + String(localized: "Return copies")
        case .hint(_, let s): s
        default: nil
        }
    }

    private var trail: String? {
        if case .clip(let c) = item { return c.date.formatted(.relative(presentation: .named)) }
        return nil
    }
}
