import AppKit
import ApolloShellCore
import SwiftUI

enum NexusSection: CaseIterable, Identifiable {
    case general, panels, about

    var id: Self { self }

    var title: String? {
        switch self {
        case .general: nil
        case .panels: String(localized: "Shell")
        case .about: nil
        }
    }
}

enum NexusPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general, hotKeys, bar, utilities, launcher, dashboard, lyrics, desktop, themes, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .hotKeys: String(localized: "Shortcuts")
        case .bar: String(localized: "Bar")
        case .utilities: String(localized: "Quick Actions")
        case .launcher: String(localized: "Launcher")
        case .dashboard: String(localized: "Dashboard")
        case .lyrics: String(localized: "Lyrics")
        case .desktop: String(localized: "Desktop")
        case .themes: String(localized: "Themes")
        case .about: String(localized: "About")
        }
    }

    var subtitle: String {
        switch self {
        case .general: String(localized: "Start at login, permissions and file manager.")
        case .hotKeys: String(localized: "Global shortcuts for Launcher, Dashboard, Quick Actions and Nexus.")
        case .bar: String(localized: "The building blocks of the bar: arrange, add, configure, and choose its edge.")
        case .utilities: String(localized: "Cards and quick toggles in the Quick Actions panel.")
        case .launcher: String(localized: "The pinned apps that appear at the top without a search text.")
        case .dashboard: String(localized: "Pages and widgets, edited right in the Dashboard. Plus where the weather comes from.")
        case .lyrics: String(localized: "Synced lyrics in the Dashboard and on the desktop, word by word.")
        case .desktop: String(localized: "The desktop clock, the OSD, panels that open on hover and which events show a toast.")
        case .themes: String(localized: "The look of the whole shell, from one CSS file.")
        case .about: String(localized: "Version, updates, crash reports and system.")
        }
    }

    var symbol: String {
        switch self {
        case .general: "switch.2"
        case .hotKeys: "command"
        case .bar: "sidebar.left"
        case .utilities: "slider.horizontal.3"
        case .launcher: "magnifyingglass"
        case .dashboard: "square.grid.2x2"
        case .lyrics: "quote.bubble"
        case .desktop: "desktopcomputer"
        case .themes: "paintpalette"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .hotKeys: .pink
        case .bar: .blue
        case .utilities: .green
        case .launcher: .purple
        case .dashboard: .indigo
        case .lyrics: .mint
        case .desktop: .teal
        case .themes: .pink
        case .about: .gray
        }
    }

    var section: NexusSection {
        switch self {
        case .general, .hotKeys: .general
        case .bar, .utilities, .launcher, .dashboard, .lyrics, .desktop, .themes: .panels
        case .about: .about
        }
    }

    var keywords: [String] {
        switch self {
        case .general: ["autostart", "login", "permissions", "accessibility", "finder"]
        case .hotKeys: ["hotkey", "keyboard", "keys", "hyper"]
        case .bar: ["taskbar", "dock", "spaces", "status", "sidebar"]
        case .utilities: ["utilities", "control center", "toggles"]
        case .launcher: ["apps", "pinned", "spotlight"]
        case .dashboard: ["widgets", "weather", "bento"]
        case .lyrics: ["songtext", "karaoke", "music"]
        case .desktop: ["clock", "osd", "toasts", "hover", "notifications"]
        case .themes: ["css", "colors", "appearance", "look"]
        case .about: ["version", "update", "reset", "uninstall", "backup"]
        }
    }

    static let index: [SettingsPage] = allCases.map { SettingsPage(id: $0.rawValue, title: $0.title, keys: $0.keywords) }

    var key: String {
        let i = (Self.allCases.firstIndex(of: self) ?? 0) + 1
        return "⌘" + String(i % 10)
    }
}

@MainActor
@Observable
final class NexusState {
    var page: NexusPage? = .bar
    var search = "" {
        didSet { if search != oldValue { sel = 0 } }
    }
    var sel = 0
    var flash: String?
    var focus = 0
    @ObservationIgnored var peek: (Bool) -> Void = { _ in }
    @ObservationIgnored private var fade: Task<Void, Never>?

    var searching: Bool { !SettingsQuery(search).isEmpty }

    func go(_ p: NexusPage) {
        search = ""
        page = p
    }

    func step(_ n: Int) {
        let all = NexusPage.allCases
        let i = all.firstIndex(of: page ?? .bar) ?? 0
        page = all[min(max(i + n, 0), all.count - 1)]
    }

    func pick(_ n: Int) {
        let all = NexusPage.allCases
        guard all.indices.contains(n) else { return }
        go(all[n])
    }

    func jump(_ h: SettingsHit) {
        switch h {
        case .page(let p, _):
            go(NexusPage(rawValue: p.id) ?? .bar)
        case .setting(let d, _):
            show(d)
        }
    }

    func show(_ d: SettingDef) {
        search = ""
        page = NexusPage(rawValue: d.page) ?? page
        flash = d.kind == .link ? "g:" + d.group : d.id
        fade?.cancel()
        fade = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            self?.flash = nil
        }
    }
}

struct NexusSkin {
    var look = ShellSettings.NexusLook.graphite

    var card: Color { look == .plain ? .clear : Color.primary.opacity(look == .glass ? 0.07 : 0.04) }
    var line: Color { Color.primary.opacity(look == .plain ? 0.16 : 0.09) }
    var r: CGFloat { look == .plain ? 6 : 10 }
}

private struct NexusSkinKey: EnvironmentKey {
    static let defaultValue = NexusSkin()
}

private struct NexusMonoKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nexusSkin: NexusSkin {
        get { self[NexusSkinKey.self] }
        set { self[NexusSkinKey.self] = newValue }
    }

    var nexusMono: Bool {
        get { self[NexusMonoKey.self] }
        set { self[NexusMonoKey.self] = newValue }
    }
}

private struct NexusGroupKey: ContainerValueKey {
    static let defaultValue: String? = nil
}

extension ContainerValues {
    var nexusGroup: String? {
        get { self[NexusGroupKey.self] }
        set { self[NexusGroupKey.self] = newValue }
    }
}

extension View {
    func nexusGroup(_ g: String) -> some View { containerValue(\.nexusGroup, g) }
}

struct NexusFx: NSViewRepresentable {
    let m: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = m
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = m }
}

struct NexusView: View {
    @Bindable var state: NexusState
    let settings: ShellSettingsStore
    let pinned: NexusPinnedModel
    let weather: NexusWeatherModel
    let providers: NexusProvidersModel
    let system: NexusSystemInfo
    let shell: NexusShellParts

    @Environment(\.shellStyle) private var style

    var body: some View {
        let skin = NexusSkin(look: settings.settings.nexus.look)
        let hits = SettingsIndex.search(state.search, in: settings.settings, pages: NexusPage.index)
        HStack(spacing: 0) {
            NexusRail(state: state, store: settings, hits: hits)
                .frame(width: 212)
                .background { rail(skin) }
            Rectangle().fill(skin.line).frame(width: 1)
            Group {
                if state.searching {
                    NexusResults(state: state, store: settings, hits: hits)
                } else {
                    NexusDetail(page: state.page ?? .bar, settings: settings, pinned: pinned, weather: weather,
                                providers: providers, system: system, shell: shell)
                        .id(state.page)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { main(skin) }
        }
        .ignoresSafeArea()
        .environment(\.nexusSkin, skin)
        .environment(\.nexusMono, true)
        .environment(state)
        .frame(minWidth: 720, minHeight: 440)
    }

    @ViewBuilder private func rail(_ k: NexusSkin) -> some View {
        if style.paintsSurface {
            Rectangle().fill(style.surfaceFill).overlay(Color.primary.opacity(0.04))
        } else if k.look == .glass {
            NexusFx(m: .sidebar)
        } else {
            Color(nsColor: .windowBackgroundColor).overlay(Color.primary.opacity(k.look == .plain ? 0 : 0.035))
        }
    }

    @ViewBuilder private func main(_ k: NexusSkin) -> some View {
        if style.paintsSurface {
            Rectangle().fill(style.surfaceFill)
        } else if k.look == .glass {
            NexusFx(m: .underWindowBackground)
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}

struct NexusShellParts {
    let hotKeys: HotKeyCenter
    let autostart: OnboardingAutostartModel
    let permissions: OnboardingPermissions
    let updates: UpdateController
    let themes: ThemeStore?
    var showOnboarding: @MainActor () -> Void = {}
}

struct NexusRail: View {
    @Bindable var state: NexusState
    let store: ShellSettingsStore
    let hits: [SettingsHit]

    @FocusState private var typing: Bool
    @Namespace private var ns
    @Environment(\.shellStyle) private var style

    private static let spring = Animation.spring(response: 0.26, dampingFraction: 0.76)

    var body: some View {
        let cnt = SettingsIndex.counts(hits)
        let busy = state.searching
        let mod = SettingsIndex.modified(in: store.settings).count
        VStack(alignment: .leading, spacing: 0) {
            field
                .padding(.horizontal, 10)
                .padding(.top, 46)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(NexusSection.allCases) { sec in
                        if let t = sec.title {
                            Text(t)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 8)
                                .padding(.top, 14)
                                .padding(.bottom, 4)
                        } else if sec == .about {
                            Color.clear.frame(height: 12)
                        }
                        ForEach(NexusPage.allCases.filter { $0.section == sec }) { p in
                            row(p, n: cnt[p.rawValue], busy: busy)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .animation(Self.spring, value: state.page)
            }
            .scrollIndicators(.never)
            foot(mod)
        }
        .onChange(of: state.focus) { typing = true }
        .onAppear { typing = true }
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search settings", text: $state.search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($typing)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) {
                    guard !state.search.isEmpty else { return .ignored }
                    state.search = ""
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { k in
                    enter(flip: k.modifiers.contains(.command))
                    return .handled
                }
            if state.search.isEmpty {
                Text("⌘F")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else {
                Button { state.search = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(style.accent.opacity(typing ? 0.7 : 0), lineWidth: 1.5))
    }

    private func row(_ p: NexusPage, n: Int?, busy: Bool) -> some View {
        let on = !busy && state.page == p
        return HStack(spacing: 9) {
            Image(systemName: p.symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(on ? AnyShapeStyle(style.accent) : AnyShapeStyle(.secondary))
            Text(p.title)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 4)
            if busy, let n {
                Text("\(n)")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if on {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .matchedGeometryEffect(id: "sel", in: ns)
            }
        }
        .opacity(busy && n == nil ? 0.38 : 1)
        .contentShape(.rect)
        .onTapGesture { state.go(p) }
        .help(p.key)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func foot(_ mod: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                state.search = "@modified"
                state.focus += 1
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(mod > 0 ? AnyShapeStyle(style.accent) : AnyShapeStyle(.tertiary)).frame(width: 6, height: 6)
                    Text(mod == 0 ? String(localized: "All defaults") : String(localized: "\(mod) modified"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(mod == 0)
            .help("Show every setting you changed")
            Spacer()
            Image(systemName: "eye")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(5)
                .contentShape(.rect)
                .onLongPressGesture(minimumDuration: 30, maximumDistance: 400, perform: {}, onPressingChanged: { state.peek($0) })
                .help("Hold to see the desktop behind Nexus (hold ⌘P)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func move(_ n: Int) {
        if state.searching {
            state.sel = min(max(state.sel + n, 0), max(hits.count - 1, 0))
        } else {
            state.step(n)
        }
    }

    private func enter(flip: Bool) {
        guard state.searching, hits.indices.contains(state.sel) else { return }
        let h = hits[state.sel]
        if flip, case .setting(let d, _) = h, d.kind == .toggle, d.enabled(in: store.settings) {
            store.nxFlip(d)
        } else {
            state.jump(h)
        }
    }
}

struct NexusResults: View {
    @Bindable var state: NexusState
    let store: ShellSettingsStore
    let hits: [SettingsHit]

    @Environment(\.shellStyle) private var style

    var body: some View {
        let q = SettingsQuery(state.search)
        ScrollViewReader { r in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(hits.isEmpty ? String(localized: "No settings match")
                             : q.modified ? String(localized: "\(hits.count) modified") : String(localized: "\(hits.count) results"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        if q.modified, !hits.isEmpty {
                            Button("Reset All") { store.nxReset(hits) }
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    ForEach(Array(hits.enumerated()), id: \.element.id) { i, h in
                        NexusHitRow(h: h, on: i == state.sel, store: store)
                            .id(h.id)
                            .onTapGesture { state.jump(h) }
                    }
                    if !hits.isEmpty {
                        Text("↑↓ move   ⏎ open   ⌘⏎ switch   esc clear")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 48)
                .padding(.bottom, 24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: state.sel) { _, i in
                if hits.indices.contains(i) { r.scrollTo(hits[i].id) }
            }
        }
    }
}

struct NexusHitRow: View {
    let h: SettingsHit
    let on: Bool
    let store: ShellSettingsStore

    @Environment(\.shellStyle) private var style

    var body: some View {
        let p = NexusPage(rawValue: h.page) ?? .bar
        HStack(spacing: 11) {
            Image(systemName: p.symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(on ? AnyShapeStyle(style.accent) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
            switch h {
            case .page:
                Text(p.title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 12)
                Text("Page").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.tertiary)
            case .setting(let d, _):
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(d.title).font(.system(size: 13, weight: .medium))
                        if d.modified(in: store.settings) {
                            Circle().fill(style.accent).frame(width: 5, height: 5)
                        }
                    }
                    Text(d.help.isEmpty ? "\(p.title) › \(d.group)" : "\(p.title) › \(d.group)  ·  \(d.help)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if d.kind == .link {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                } else {
                    if d.modified(in: store.settings) {
                        Button { store.nxReset(d) } label: {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 10.5, weight: .semibold))
                        }
                        .buttonStyle(.borderless)
                        .help("Reset to \(d.standardLabel)")
                    }
                    NexusControl(d: d, store: store)
                        .disabled(!d.enabled(in: store.settings))
                        .opacity(d.enabled(in: store.settings) ? 1 : 0.45)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(on ? 0.08 : 0)))
        .contentShape(.rect)
    }
}

struct NexusDetail: View {
    let page: NexusPage
    let settings: ShellSettingsStore
    let pinned: NexusPinnedModel
    let weather: NexusWeatherModel
    let providers: NexusProvidersModel
    let system: NexusSystemInfo
    let shell: NexusShellParts

    var body: some View {
        switch page {
        case .general: NexusGeneralPage(store: settings, autostart: shell.autostart, permissions: shell.permissions, providers: providers)
        case .hotKeys: NexusHotKeysPage(store: settings, center: shell.hotKeys)
        case .bar: NexusBarPage(store: settings)
        case .utilities: UtilitiesEditorPage(store: settings)
        case .launcher: NexusLauncherPage(model: pinned)
        case .dashboard: NexusDashboardPage(store: settings, model: weather, providers: providers)
        case .lyrics: NexusLyricsPage(store: settings)
        case .desktop: NexusDesktopPage(store: settings)
        case .themes: NexusThemesPage(store: settings, themes: shell.themes)
        case .about: NexusAboutPage(system: system, store: settings, updates: shell.updates, showOnboarding: shell.showOnboarding)
        }
    }
}

extension SettingDef {
    var standardLabel: String {
        var s = ShellSettings.firstLaunch
        reset(in: &s)
        return label(in: s)
    }
}

extension ShellSettingsStore {
    func nxWrite(_ d: SettingDef, _ v: String) {
        var s = settings
        d.write(v, to: &s)
        settings = s
        if (d.id == "lyrics.pulse" || d.id == "lyrics.sync"), v == "1", !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    func nxFlip(_ d: SettingDef) {
        nxWrite(d, d.isOn(in: settings) ? "0" : "1")
    }

    func nxReset(_ d: SettingDef) {
        var s = settings
        d.reset(in: &s)
        settings = s
    }

    func nxReset(_ hits: [SettingsHit]) {
        var s = settings
        for h in hits {
            if case .setting(let d, _) = h { d.reset(in: &s) }
        }
        settings = s
    }

    func nxBool(_ d: SettingDef) -> Binding<Bool> {
        Binding(get: { d.isOn(in: self.settings) }, set: { self.nxWrite(d, $0 ? "1" : "0") })
    }

    func nxText(_ d: SettingDef) -> Binding<String> {
        Binding(get: { d.value(in: self.settings) }, set: { self.nxWrite(d, $0) })
    }
}

struct NexusControl: View {
    let d: SettingDef
    let store: ShellSettingsStore

    var body: some View {
        switch d.kind {
        case .toggle:
            Toggle("", isOn: store.nxBool(d))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        case .choice(let o):
            if o.count <= 3 {
                Picker("", selection: store.nxText(d)) {
                    ForEach(o) { Text($0.title).tag($0.id) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            } else {
                Picker("", selection: store.nxText(d)) {
                    ForEach(o) { Text($0.title).tag($0.id) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        case .link:
            EmptyView()
        }
    }
}

struct NexusLabel: View {
    let title: Text
    var tip: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title.font(.system(size: 13))
            if let tip {
                tip.font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct NexusSettingRow: View {
    let d: SettingDef?
    let store: ShellSettingsStore

    @Environment(NexusState.self) private var st: NexusState?
    @Environment(\.shellStyle) private var style
    @State private var hov = false

    init(_ id: String, _ store: ShellSettingsStore) {
        d = SettingsIndex.find(id)
        self.store = store
    }

    var body: some View {
        if let d {
            let s = store.settings
            let mod = d.modified(in: s)
            let en = d.enabled(in: s)
            let fl = st?.flash == d.id
            HStack(spacing: 12) {
                NexusLabel(title: Text(d.title), tip: d.help.isEmpty ? nil : Text(d.help))
                Spacer(minLength: 12)
                if mod {
                    Button { store.nxReset(d) } label: {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to \(d.standardLabel)")
                    .opacity(hov ? 1 : 0)
                }
                NexusControl(d: d, store: store)
            }
            .opacity(en ? 1 : 0.45)
            .disabled(!en)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(style.accent)
                    .frame(width: 5, height: 5)
                    .scaleEffect(mod ? 1 : 0.01)
                    .offset(x: -10)
                    .animation(.spring(response: 0.24, dampingFraction: 0.55), value: mod)
            }
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(style.accent.opacity(fl ? 0.18 : 0))
                    .padding(.horizontal, -9)
                    .padding(.vertical, -6)
                    .scaleEffect(fl ? 1 : 0.985)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: fl)
            }
            .onHover { hov = $0 }
            .contextMenu {
                Button("Reset to Default (\(d.standardLabel))") { store.nxReset(d) }.disabled(!mod)
            }
            .id(d.id)
        }
    }
}

struct NexusLCS: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.label.font(.system(size: 13))
            Spacer(minLength: 12)
            configuration.content
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct NexusPageForm<Content: View>: View {
    let page: NexusPage
    var title: String?
    var subtitle: String?
    @ViewBuilder let content: Content

    @Environment(NexusState.self) private var st: NexusState?
    @Environment(\.nexusSkin) private var skin
    @Environment(\.shellStyle) private var style

    var body: some View {
        ScrollViewReader { r in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title ?? page.title)
                            .font(.system(size: 24, weight: .bold))
                        Text(subtitle ?? page.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 2)
                    ForEach(sections: content) { sec in
                        block(sec)
                    }
                }
                .labeledContentStyle(NexusLCS())
                .padding(.horizontal, 28)
                .padding(.top, 46)
                .padding(.bottom, 28)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: st?.flash, initial: true) { _, f in
                guard let f else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { r.scrollTo(f, anchor: .center) }
            }
        }
    }

    @ViewBuilder private func block(_ sec: SectionConfiguration) -> some View {
        let g = sec.containerValues.nexusGroup
        let fl = g != nil && st?.flash == "g:" + (g ?? "")
        let rows = Array(sec.content)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                if !sec.header.isEmpty {
                    sec.header
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 2)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, v in
                        v.padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        if i < rows.count - 1 {
                            Rectangle().fill(skin.line).frame(height: 1).padding(.leading, 14)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: skin.r, style: .continuous).fill(skin.card))
                .overlay(RoundedRectangle(cornerRadius: skin.r, style: .continuous)
                    .strokeBorder(fl ? style.accent : skin.line, lineWidth: fl ? 2 : 1))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: fl)
                if !sec.footer.isEmpty {
                    sec.footer
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                }
            }
            .id(g.map { "g:" + $0 } ?? "s:" + String(describing: sec.id))
        }
    }
}

struct NexusTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    @Environment(\.nexusMono) private var mono

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(mono ? Color.primary.opacity(0.07) : tint)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(mono ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
            }
            .accessibilityHidden(true)
    }
}

struct NexusToggle: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var tip: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            NexusLabel(title: Text(title), tip: (tip ?? subtitle).map { Text($0) })
            Spacer(minLength: 12)
            Toggle(isOn: $isOn) { Text(title) }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

struct NexusPick<C: View>: View {
    let title: LocalizedStringKey
    var tip: LocalizedStringKey?
    @ViewBuilder let content: C

    var body: some View {
        HStack(spacing: 12) {
            NexusLabel(title: Text(title), tip: tip.map { Text($0) })
            Spacer(minLength: 12)
            content.labelsHidden().fixedSize()
        }
    }
}

struct NexusTip: View {
    let text: LocalizedStringKey

    var body: some View {
        Image(systemName: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(text)
            .accessibilityLabel(text)
    }
}

struct NexusTipHeader: View {
    let title: LocalizedStringKey
    let tip: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(tip)
                .font(.system(size: 11.5))
                .textCase(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Spruenge in die Systemeinstellungen.
///
/// Die Bereichs-Kennungen sind die Bundle-IDs der Einstellungs-Erweiterungen
/// in /System/Library/ExtensionKit/Extensions (gemessen 14.09., macOS 26.6).
/// Ohne Bereich wird die App ueber ihre Bundle-ID geoeffnet: das klappt
/// sicher, egal wie sie nach Updates heisst oder wo sie liegt.
enum NexusSystemSettings {
    enum Pane: String {
        case wallpaper = "com.apple.Wallpaper-Settings.extension"
        case appearance = "com.apple.Appearance-Settings.extension"
        case network = "com.apple.Network-Settings.extension"
        case bluetooth = "com.apple.BluetoothSettings"
        case sound = "com.apple.Sound-Settings.extension"
        case notifications = "com.apple.Notifications-Settings.extension"
        case softwareUpdate = "com.apple.Software-Update-Settings.extension"
        case language = "com.apple.Localization-Settings.extension"
        case about = "com.apple.SystemProfiler.AboutExtension"
        /// Datenschutz & Sicherheit > Bedienungshilfen (Anker aus den
        /// Suchbegriffen der Erweiterung, gemessen 14.09., macOS 26.6).
        case accessibility = "com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
    }

    static func open(_ pane: Pane?) {
        if let pane, let url = URL(string: "x-apple.systempreferences:\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
            return
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }
}
