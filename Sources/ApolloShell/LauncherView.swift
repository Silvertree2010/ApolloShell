import ApolloShellCore
import SwiftUI

/// Suchfeld oben, darunter die scrollbare App-Liste. Der Glas-Hintergrund
/// kommt vom NSGlassEffectView drumherum (siehe LauncherController).
struct LauncherView: View {
    @Bindable var model: LauncherModel
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

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
                Text("Keine App gefunden")
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
            TextField("Suchen …", text: $model.query)
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
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, app in
                        AppRow(
                            app: app,
                            icon: model.icon(for: app),
                            selected: index == model.selectedIndex
                        )
                        .id(app.id)
                        .onTapGesture {
                            model.selectedIndex = index
                            model.launchSelected()
                        }
                        // Rechtsklick wie im Dock: das Menue der App selbst.
                        // Es kommt aus Apples Dock und braucht einen Moment,
                        // deshalb AppKit statt `contextMenu`.
                        .overlay {
                            RightClickCatcher { view in
                                model.selectedIndex = index
                                model.onRightClick(app, view)
                            }
                        }
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

private struct AppRow: View {
    let app: AppEntry
    let icon: NSImage
    let selected: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var style: ShellStyle { ShellTheme.style(colorScheme) }

    var body: some View {
        let radius = style.controlRadius(10)
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)
            Text(app.name)
                .font(style.font(size: 15))
                .lineLimit(1)
                .foregroundStyle(style.paint(.text, or: .primary))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Mit Theme gibt `--apollo-launcher-row-height` die Zeilenhoehe vor;
        // ohne Theme bestimmt sie wie bisher der Inhalt.
        .frame(minHeight: style.length(.launcherRowHeight))
        .background {
            // Mit Theme faerbt `--apollo-launcher-highlight-color` die
            // gewaehlte Zeile (oder der Verlauf daneben).
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
