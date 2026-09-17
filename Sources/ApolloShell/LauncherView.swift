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
            Divider().opacity(0.4)
            if model.results.isEmpty {
                Text("Keine App gefunden")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        // Bei jedem Oeffnen sofort lostippen koennen.
        .onChange(of: model.openCount, initial: true) { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(style.font(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
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
                        // Rechtsklick wie im Dock: die Befehle der App und
                        // der Sprung in den Dateimanager.
                        .contextMenu {
                            LauncherRowMenu(model: model, app: app)
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

/// Das Kontextmenue einer Zeile. Die Befehle kommen aus der Menueleiste der
/// App (`DockAppCommands`) und stehen deshalb nur, solange sie laeuft - wie
/// im Dock-Menue der Leiste.
private struct LauncherRowMenu: View {
    let model: LauncherModel
    let app: AppEntry

    var body: some View {
        let native = model.nativeItems(app)
        Button("Öffnen") { model.onLaunch(app) }
        if native.isEmpty {
            // Apples Dock kennt diese App nicht (nicht dort, nicht laufend):
            // dann die Befehle aus ihrer Menueleiste.
            let commands = model.commands(app)
            if !commands.isEmpty {
                Divider()
                ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
                    Button(command.title) { model.onCommand(app, command.kind) }
                }
            }
        } else {
            Divider()
            LauncherNativeItems(model: model, app: app, items: native)
        }
        Divider()
        Button("Im Finder zeigen") { model.onReveal(app) }
    }
}

/// Apples Eintraege, samt Untermenues.
private struct LauncherNativeItems: View {
    let model: LauncherModel
    let app: AppEntry
    let items: [LauncherMenuItem]

    var body: some View {
        ForEach(items) { item in
            if item.separator {
                Divider()
            } else if item.children.isEmpty {
                Button(item.title) { model.onNativeItem(app, item) }
                    .disabled(!item.enabled)
            } else {
                Menu(item.title) {
                    LauncherNativeItems(model: model, app: app, items: item.children)
                }
                .disabled(!item.enabled)
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            // Mit Theme faerbt `--apollo-launcher-highlight-color` die
            // gewaehlte Zeile (oder der Verlauf daneben).
            if selected {
                if style.isThemed {
                    RoundedRectangle(cornerRadius: radius).fill(style.launcherHighlightFill)
                } else {
                    RoundedRectangle(cornerRadius: radius).fill(Color.primary.opacity(0.12))
                }
            }
        }
        .contentShape(.rect)
    }
}
