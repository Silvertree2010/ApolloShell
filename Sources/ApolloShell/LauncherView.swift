import ApolloShellCore
import SwiftUI

/// Suchfeld oben, darunter die scrollbare App-Liste. Der Glas-Hintergrund
/// kommt vom NSGlassEffectView drumherum (siehe LauncherController).
struct LauncherView: View {
    @Bindable var model: LauncherModel
    @FocusState private var searchFocused: Bool

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
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Suchen …", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
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

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)
            Text(app.name)
                .font(.system(size: 15))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            selected ? Color.primary.opacity(0.12) : .clear,
            in: .rect(cornerRadius: 10)
        )
        .contentShape(.rect)
    }
}
