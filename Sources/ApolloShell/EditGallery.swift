import ApolloShellCore
import SwiftUI

// Inhalt von Werkzeugleiste und Galerie des globalen Bearbeitungsmodus
// (Task 3). Reine SwiftUI-Ansichten, gehostet in `FloatingGlassPanel`
// (`EditModeWindows.swift`) und - fuer die Bildprobe `--render-edit` - direkt
// in `RenderMode.swift`.

/// Nutzlast fuer das Ziehen eines Schnellschalters aus der Galerie ins
/// Kontrollzentrum-Panel (Ziel folgt in Task 5).
enum UtilitiesToggleDragPayload {
    static let prefix = "apolloshell.toggle:"
    static func string(for kind: UtilitiesToggleKind) -> String { prefix + kind.rawValue }
    static func kind(from string: String) -> UtilitiesToggleKind? {
        guard string.hasPrefix(prefix) else { return nil }
        return UtilitiesToggleKind(rawValue: String(string.dropFirst(prefix.count)))
    }
}

/// Nutzlast fuer das Ziehen einer Kontrollzentrum-Karte aus der Galerie.
enum UtilitiesCardDragPayload {
    static let prefix = "apolloshell.card:"
    static func string(for kind: UtilitiesCardKind) -> String { prefix + kind.rawValue }
    static func kind(from string: String) -> UtilitiesCardKind? {
        guard string.hasPrefix(prefix) else { return nil }
        return UtilitiesCardKind(rawValue: String(string.dropFirst(prefix.count)))
    }
}

/// Werkzeugleiste unten mittig: **+** (Galerie auf/zu), **Abbrechen**,
/// **Fertig**. Mit ungesicherten Aenderungen und Esc (Task 6) tritt an ihre
/// Stelle kurz eine Nachfrage.
struct EditToolbarView: View {
    @Bindable var editor: ShellEditor
    @Environment(\.shellStyle) private var style

    var body: some View {
        Group {
            if editor.pendingCancelConfirmation {
                cancelConfirmation
            } else {
                controls
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .fixedSize()
        .animation(.easeOut(duration: 0.15), value: editor.pendingCancelConfirmation)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                editor.galleryVisible.toggle()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    // Der ganze Kreis, nicht nur das Pluszeichen.
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: .circle)
            .help("Element hinzufügen")
            .accessibilityLabel("Hinzufügen")

            Button("Abbrechen") {
                editor.cancel()
            }
            .buttonStyle(.bordered)

            Button("Fertig") {
                editor.done()
            }
            .buttonStyle(.borderedProminent)
            .tint(style.accent)
        }
    }

    /// „Änderungen verwerfen?“ - Esc mit ungesicherten Aenderungen
    /// (`ShellEditor.handleEscape`) zeigt das statt der drei Knoepfe oben,
    /// bis man sich entscheidet.
    private var cancelConfirmation: some View {
        HStack(spacing: 14) {
            Text("Änderungen verwerfen?")
                .font(.callout.weight(.medium))
            Button("Weiter bearbeiten") {
                editor.dismissCancelConfirmation()
            }
            .buttonStyle(.bordered)
            Button("Verwerfen", role: .destructive) {
                editor.confirmCancel()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}

/// Nur in `RenderMode --render-edit`: `ImageRenderer` zieht `.onDrag` (fuer
/// `NSItemProvider`-Ziehsitzungen AppKit-hinterlegt) offscreen als rotes
/// Verbotszeichen (dieselbe Ursache wie `.onDrop`, siehe
/// `dashboardRendersForScreenshot`). Fuers echte Fenster bleibt Ziehen immer an.
private struct GalleryRendersForScreenshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var galleryRendersForScreenshot: Bool {
        get { self[GalleryRendersForScreenshotKey.self] }
        set { self[GalleryRendersForScreenshotKey.self] = newValue }
    }
}

/// Breite der Galerie (`EditGalleryView.body`) und ihr Innenmass (Rand
/// 16 auf jeder Seite) - `GalleryGrid` rechnet direkt damit statt mit einer
/// aus `proposal` geratenen Breite (siehe dort).
// Breit und flach wie Apples Widget-Galerie: sie steht unter dem Dashboard,
// und dort ist auf 14 Zoll nur gut 300 pt Hoehe frei (vorher 560 breit mit
// vier Spalten, gut 370 hoch - sie ueberdeckte das Dashboard). 760 laesst
// rechts Platz fuer das Kontrollzentrum.
private let galleryWidth: CGFloat = 760
private let galleryContentWidth: CGFloat = galleryWidth - 2 * 16
/// Anzahl Spalten des Kachelrasters bei `galleryContentWidth`: so breit wie
/// eine Kachel (108) plus Abstand passt.
private let galleryColumns = 8

/// Reiter „Dashboard“/„Kontrollzentrum“: eigene Kapseln statt
/// `Picker(.segmented)` - AppKit-hinterlegt, `ImageRenderer` zeichnet ihn
/// offscreen als gelben Balken (dieselbe Ursache wie beim Umschalter unten),
/// und im Aussehen war er ohnehin ein Fremdkoerper neben dem Rest der Shell
/// (vergleiche die Seitenreiter des Dashboards, `DashboardView.pageButton`).
private struct GallerySurfaceTabs: View {
    @Binding var selection: WidgetSurface
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 4) {
            tab(.dashboard, title: String(localized: "Dashboard"))
            tab(.controlCentre, title: String(localized: "Kontrollzentrum"))
        }
        .padding(3)
        .background(.quaternary.opacity(0.4), in: Capsule())
    }

    private func tab(_ surface: WidgetSurface, title: String) -> some View {
        let isSelected = selection == surface
        return Button {
            selection = surface
        } label: {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    if isSelected { Capsule().fill(style.accent) }
                }
                // Ganze Kapsel klickbar, auch beim nicht gewaehlten Reiter
                // (dort ohne Hintergrund - vorher reagierte nur der Text).
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Eigener Umschalter statt `Toggle(.switch)` - derselbe AppKit-Grund wie bei
/// den Reitern oben.
private struct GalleryCheckbox: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            // Ganze Zeile klickbar, nicht nur Symbol und Buchstaben.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Festes Kachelraster in `columns` Spalten, gleich breiten Zeilen. Kein
/// `LazyVGrid`: siehe Kommentar bei `EditGalleryView.body` - fuer die feste,
/// ueberschaubare Anzahl an Kacheln (Widget-Katalog, Karten, Schnellschalter)
/// kostet das nichts, macht die Galerie aber `ImageRenderer`-tauglich.
private struct GalleryGrid: Layout {
    let columns: Int
    let spacing: CGFloat
    /// Feste Breite statt aus `proposal` geraten: in einer `ScrollView`
    /// kommt die vorgeschlagene Breite mal `nil`, mal ein Platzhalterwert -
    /// besonders offscreen bei `ImageRenderer` (Bildproben). Die Galerie hat
    /// ohnehin eine feste Breite (`EditGalleryView`), das Raster rechnet
    /// direkt mit deren Innenmass statt zu raten.
    let width: CGFloat

    private func columnWidth() -> CGFloat {
        (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let columnWidth = columnWidth()
        let rowHeight = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }.max() ?? 0
        let rows = Int((Double(subviews.count) / Double(columns)).rounded(.up))
        let height = CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = columnWidth()
        let rowHeight = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }.max() ?? 0
        for (index, subview) in subviews.enumerated() {
            let row = index / columns
            let col = index % columns
            let x = bounds.minX + CGFloat(col) * (columnWidth + spacing)
            let y = bounds.minY + CGFloat(row) * (rowHeight + spacing)
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: columnWidth, height: rowHeight))
        }
    }
}

/// Galerie: ein Reiter je Flaeche, mit Kacheln zum Ziehen oder Anklicken.
/// „Alle zeigen (erweitert)“ blendet auch Elemente der jeweils anderen
/// Flaeche ein (Spec: "not optimised" ausserhalb ihrer Heimat).
struct EditGalleryView: View {
    @Bindable var editor: ShellEditor
    @Environment(\.galleryRendersForScreenshot) private var rendersForScreenshot

    var body: some View {
        VStack(spacing: 12) {
            GallerySurfaceTabs(selection: $editor.galleryTab)

            GalleryCheckbox(title: String(localized: "Alle zeigen (erweitert)"), isOn: $editor.showsAllInGallery)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Kein `LazyVGrid`: ein eigenes, festes Raster in Zeilen statt
            // Spalten zaehlt jede Kachel sicher mit. Die `ScrollView` darueber
            // zeichnet `ImageRenderer` offscreen leer, wenn ihr Inhalt eine
            // eigene `Layout`-Kachel ist (Bildprobe `--render-edit`, gemessen
            // 19.09.) - dort faellt sie weg, das Raster steht ungeschnitten
            // da. Im echten Fenster bleibt sie: mehr Kacheln als die feste
            // Hoehe passen sonst nicht hinein.
            if rendersForScreenshot {
                galleryGrid
            } else {
                ScrollView {
                    galleryGrid
                }
                .frame(height: 200)
            }

            if let notice = editor.galleryNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(width: galleryWidth)
    }

    private var galleryGrid: some View {
        GalleryGrid(columns: galleryColumns, spacing: 10, width: galleryContentWidth) {
            switch editor.galleryTab {
            case .dashboard: dashboardTiles
            case .controlCentre: controlCentreTiles
            }
        }
        .padding(.vertical, 4)
    }

    private var dashboardTiles: some View {
        ForEach(WidgetKind.allCases.filter { editor.showsAllInGallery || $0.home == .dashboard }) { kind in
            EditGalleryTile(symbol: kind.symbol, title: kind.title, detail: sizesText(kind.sizes.count),
                            tooltip: kind.title, payload: BentoWidgetDragPayload.string(for: kind), isDisabled: false) {
                // Dieselben Favoriten wie beim Ablegen (`BentoDropDelegate.add`)
                // - sonst startete ein per Klick angelegtes Wetter-Widget ohne
                // Orte, obwohl es welche gibt (Task 3/5).
                let places = WeatherFavorites.loadLive()
                if editor.dashboard.addAtFirstFreeSpot(kind, places: places) == nil {
                    show(notice: String(localized: "Kein Platz auf dieser Seite"))
                }
            }
        }
    }

    @ViewBuilder
    private var controlCentreTiles: some View {
        ForEach(UtilitiesCardKind.allCases) { kind in
            let already = editor.utilities?.layout.isEnabled(kind) ?? true
            EditGalleryTile(symbol: kind.symbol, title: kind.title, detail: nil, tooltip: kind.summary,
                            payload: UtilitiesCardDragPayload.string(for: kind), isDisabled: already) {
                editor.setCard(kind, enabled: true)
            }
        }
        ForEach(UtilitiesToggleGroup.allCases) { group in
            ForEach(group.kinds) { kind in
                let already = editor.utilities.map { !$0.layout.canAdd(kind) } ?? false
                EditGalleryTile(symbol: kind.symbol ?? "circle", title: kind.title, detail: nil, tooltip: kind.summary,
                                payload: UtilitiesToggleDragPayload.string(for: kind), isDisabled: already) {
                    if editor.addToggle(kind) == nil {
                        show(notice: String(localized: "Gibt es schon"))
                    }
                }
            }
        }
    }

    private func sizesText(_ count: Int) -> String {
        count == 1 ? String(localized: "1 Größe") : String(localized: "\(count) Größen")
    }

    private func show(notice text: String) {
        withAnimation { editor.galleryNotice = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { editor.galleryNotice = nil }
        }
    }
}

/// Eine Kachel der Galerie: Symbol, Titel, auf Wunsch eine kurze Kennzahl
/// (Dashboard: Anzahl Groessen). Die volle Beschreibung (Kontrollzentrum:
/// `UtilitiesCardKind.summary`/`UtilitiesToggleKind.summary`, oft laenger als
/// eine Zeile) steht nur im Tooltip (`.help`) - als dritte Zeile lief sie in
/// jeder Kachel ab (Live-Test 19.09.). Ziehen setzt die Textnutzlast
/// (`apolloshell.widget:`/`.toggle:`/`.card:`), ein Klick landet an der
/// ersten freien Stelle bzw. am Ende.
private struct EditGalleryTile: View {
    let symbol: String
    let title: String
    /// Kurze Kennzahl unter dem Titel; `nil` laesst die Zeile weg.
    let detail: String?
    let tooltip: String
    let payload: String
    let isDisabled: Bool
    let action: () -> Void
    @Environment(\.galleryRendersForScreenshot) private var rendersForScreenshot

    var body: some View {
        // Kein `Button`: der verfolgt die Maus selbst und liess `.onDrag`
        // unter macOS oft gar nicht erst anfangen - Ziehen aus der Galerie
        // ging dann nicht (Live-Test 19.09.). Ein Tipp ohne Zug fuegt ein,
        // ein Zug zieht; beides vertraegt sich mit `onTapGesture`.
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .frame(height: 24)
            // Zwei Zeilen statt abgeschnitten: „Apps ausblenden“, „Wetter-
            // uebersicht“ usw. passen in 8 Spalten nicht auf eine Zeile
            // (Live-Test 19.09.: Titel stiessen an den Kachelrand). Immer
            // zwei Zeilen Platz, damit alle Kacheln gleich hoch bleiben.
            Text(title)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, 5)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cardSurface(radius: 14)
        .contentShape(.rect(cornerRadius: 14))
        .opacity(isDisabled ? 0.4 : 1)
        .onTapGesture { if !isDisabled { action() } }
        .modifier(GalleryDragModifier(payload: payload, active: !rendersForScreenshot && !isDisabled))
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !isDisabled { action() } }
    }
}

/// Haengt `.onDrag` nur ausserhalb von Bildproben an: `ImageRenderer`
/// zeichnet die AppKit-hinterlegte Ziehsitzung offscreen als rotes
/// Verbotszeichen (wie `.onDrop`, siehe `BentoDropTarget`). Das echte
/// Fenster laesst Ziehen immer an.
private struct GalleryDragModifier: ViewModifier {
    let payload: String
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrag { NSItemProvider(object: payload as NSString) }
        } else {
            content
        }
    }
}
