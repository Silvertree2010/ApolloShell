import ApolloShellCore
import SwiftUI
import UniformTypeIdentifiers

// Bearbeitungs-Oberflaeche fuer eine Bento-Seite (design/2026-09-18-bento-
// dashboard.md, Abschnitt 5; design/2026-09-18-bento-plan-edit.md Task 3):
// wackelnde, waehlbare Widgets mit `-`-Knopf und Groessen-Griff, und das
// Ziel fuer Widgets, die aus Nexus gezogen werden. `BentoPageView.swift`
// zeigt diese Bausteine nur, waehrend `editor.isEditing` gilt - die ruhige
// Ansicht bleibt unveraendert (Bildvergleich).

/// Nutzlast fuer das Ziehen eines Widgets aus Nexus in die Seite.
enum BentoWidgetDragPayload {
    static let prefix = "apolloshell.widget:"

    static func string(for kind: WidgetKind) -> String { prefix + kind.rawValue }

    static func kind(from string: String) -> WidgetKind? {
        guard string.hasPrefix(prefix) else { return nil }
        return WidgetKind(rawValue: String(string.dropFirst(prefix.count)))
    }
}

/// Genaeherter Radius der eigenen Karte einer Art, fuer den Auswahlrahmen
/// beim Bearbeiten (die Karten selbst kennt `BentoEditOverlay` nicht -
/// `WidgetView.swift` waehlt sie nach Groesse). Wo eine Art mehrere Radien
/// hat, der haeufigste; ohne eigene Karte 24 (Plan: "radius following the
/// card radius (use 24 pt if the widget has none)").
extension WidgetKind {
    var editSelectionRadius: CGFloat {
        switch self {
        case .weather: 28
        case .user: 28
        case .clock: 16
        case .calendar: 28
        case .resources: 16
        case .media: 28
        case .performanceCPU, .performanceGPU, .performanceStorage, .performanceMemory: 24
        case .performanceNetwork: 10
        case .performanceBattery: 41
        case .weatherHero: 42
        case .weatherHourly: 28
        case .weatherDaily: 24
        case .mediaPlayer: 56
        }
    }
}

/// Ueberschreibt `accessibilityReduceMotion` (systemweit, nicht setzbar) fuer
/// Bildproben (`RenderMode --render-dashboard`, Ordner `edit/`); `nil` laesst
/// den echten Systemwert gelten.
private struct DashboardReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var dashboardReducesMotionOverride: Bool? {
        get { self[DashboardReduceMotionKey.self] }
        set { self[DashboardReduceMotionKey.self] = newValue }
    }
}

/// `true` nur in `RenderMode --render-dashboard`s `edit/`-Bildproben:
/// `ImageRenderer` zeichnet AppKit-hinterlegte Bausteine offscreen nicht
/// (gemessen 18.09.: `.onDrop` ergab ein rotes Verbotszeichen quer ueber der
/// ganzen Seite statt des Ziels) - das Ablegeziel bleibt fuer die Bildprobe
/// darum weg. Das echte Dashboard setzt diesen Schalter nie; `.onDrop`
/// bleibt dort wie gewohnt aktiv.
private struct RendersForScreenshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var dashboardRendersForScreenshot: Bool {
        get { self[RendersForScreenshotKey.self] }
        set { self[RendersForScreenshotKey.self] = newValue }
    }
}

/// Ein Widget waehrend der Bearbeitung: Inhalt abgeschaltet (keine
/// Medien-Knoepfe, keine Kalenderpfeile), wackelt, laesst sich waehlen,
/// ziehen, in der Groesse aendern und entfernen.
struct EditableWidgetView: View {
    let widget: WidgetInstance
    let context: WidgetContext
    var editor: DashboardEditor
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dashboardReducesMotionOverride) private var reduceMotionOverride
    @Environment(\.shellStyle) private var style
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    @State private var dragFrame: WidgetFrame?
    @State private var dragValid = true
    @State private var resizeFrame: WidgetFrame?
    @State private var resizeValid = true
    @State private var isDeleting = false
    @State private var wobble: Double = 0

    /// Verschiedene Phasen, damit Widgets nicht im Gleichtakt wackeln.
    private var phase: Double {
        Double(abs(widget.id.hashValue) % 260) / 1000
    }

    private var frame: WidgetFrame { resizeFrame ?? dragFrame ?? widget.frame }
    private var isSelected: Bool { editor.selectedWidgetID == widget.id }
    private var isTransforming: Bool { dragFrame != nil || resizeFrame != nil }
    private var isValid: Bool { dragFrame != nil ? dragValid : resizeValid }

    private var outlineColor: Color? {
        if isTransforming { return isValid ? style.accent : Color.red }
        return isSelected ? style.accent : nil
    }

    var body: some View {
        WidgetView(widget: widget, context: context)
            .allowsHitTesting(false)
            .frame(width: frame.width, height: frame.height)
            .overlay {
                let shape = RoundedRectangle(cornerRadius: widget.kind.editSelectionRadius, style: .continuous)
                if let outlineColor {
                    shape.strokeBorder(outlineColor, lineWidth: 2)
                } else if reduceMotion {
                    shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) { minusBadge }
            .overlay(alignment: .bottomTrailing) { resizeHandle }
            // Nach den Overlays: Minus und Griff wackeln mit dem Widget.
            .rotationEffect(.degrees(reduceMotion ? 0 : wobble))
            .opacity(isDeleting ? 0 : 1)
            .scaleEffect(isDeleting ? 0.6 : 1)
            .offset(x: frame.x, y: frame.y)
            .zIndex(isSelected || isTransforming ? 1 : 0)
            .gesture(dragGesture)
            // Ein Tipp ohne Zug: `DragGesture` erkennt Bewegungen unter
            // `minimumDistance` gar nicht erst, waehlt also nie aus - ein
            // eigenes `TapGesture` daneben waehlt ohne zu verschieben.
            .simultaneousGesture(TapGesture().onEnded { editor.selectedWidgetID = widget.id })
            .onAppear { startWobble() }
            .onChange(of: reduceMotion) { _, _ in startWobble() }
            // Optionen des gewaehlten Widgets (Task 4): dieselben Regler wie
            // im alten Nexus-Editor (`WidgetOptionsView`), jetzt direkt neben
            // dem Widget statt in einer eigenen Spalte. Schliesst sich von
            // selbst, wenn die Auswahl faellt oder die Seite wechselt - beides
            // raeumt `editor.selectedWidgetID` auf, und der Popover haengt
            // nur an `isSelected`.
            .popover(isPresented: Binding(
                get: { isSelected },
                set: { if !$0 { editor.selectedWidgetID = nil } }
            ), arrowEdge: .trailing) {
                Form {
                    WidgetOptionsView(editor: editor, widget: widget, weatherFile: ShellFiles.live.weather)
                }
                .formStyle(.grouped)
                .frame(width: 280)
                .frame(minHeight: 120, maxHeight: 420)
            }
    }

    /// Caelestia/Apple: leichtes, staendiges Wackeln, solange man nicht
    /// gerade zieht. `withAnimation` mit `.repeatForever` und `phase`-Verzug,
    /// damit nicht alle Widgets im gleichen Takt kippen.
    private func startWobble() {
        guard !reduceMotion else {
            wobble = 0
            return
        }
        // 0.6 Grad war ihm zu stark (Live-Test 19.09.): halb so viel, etwas ruhiger.
        wobble = -0.3
        withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true).delay(phase)) {
            wobble = 0.3
        }
    }

    private var minusBadge: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { isDeleting = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { editor.remove(widget.id) }
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .background(.regularMaterial, in: .circle)
        }
        .buttonStyle(.plain)
        .offset(x: -11, y: -11)
        .help("Entfernen")
        .accessibilityLabel("\(widget.kind.title) entfernen")
    }

    private var resizeHandle: some View {
        ResizeHandleShape()
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .offset(x: -6, y: -6)
            .gesture(resizeGesture)
            .accessibilityLabel("\(widget.kind.title) Größe ändern")
    }

    /// Ziehen des Widgets: `editor.previewMove` live, Loslassen uebernimmt
    /// gueltig oder springt zurueck. Waehlt das Widget in jedem Fall aus.
    private var dragGesture: some Gesture {
        // Benannter Bezugsraum auf der Seite (`BentoPageView`), nicht
        // `.local`: der eigene Rahmen des Widgets waechst waehrend eines
        // Zugs mit (Vorschau), `.local`-Werte haetten sich also mitten im
        // Ziehen verschoben (gemessen: Ruckeln).
        DragGesture(minimumDistance: 2, coordinateSpace: .named(BentoPageView.coordinateSpaceName))
            .onChanged { value in
                let proposed = WidgetFrame(x: widget.frame.x + value.translation.width,
                                           y: widget.frame.y + value.translation.height,
                                           width: widget.frame.width, height: widget.frame.height)
                guard let preview = editor.previewMove(widget.id, proposed: proposed) else { return }
                dragFrame = preview.frame
                dragValid = preview.valid
            }
            .onEnded { _ in
                editor.selectedWidgetID = widget.id
                if let dragFrame, dragValid {
                    editor.commit(widget.id, frame: dragFrame)
                }
                withAnimation(DashboardView.motion) { dragFrame = nil }
                dragValid = true
            }
    }

    /// Griff unten rechts: `editor.previewResize` live, Loslassen uebernimmt
    /// gueltig oder springt zurueck.
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(BentoPageView.coordinateSpaceName))
            .onChanged { value in
                let proposedWidth = widget.frame.width + value.translation.width
                let proposedHeight = widget.frame.height + value.translation.height
                guard let preview = editor.previewResize(widget.id, proposedWidth: proposedWidth,
                                                         proposedHeight: proposedHeight) else { return }
                resizeFrame = preview.frame
                resizeValid = preview.valid
            }
            .onEnded { _ in
                editor.selectedWidgetID = widget.id
                if let resizeFrame, resizeValid {
                    editor.commit(widget.id, frame: resizeFrame)
                }
                withAnimation(DashboardView.motion) { resizeFrame = nil }
                resizeValid = true
            }
    }
}

/// Viertelkreis-Griff wie bei Apples Widget-Bearbeitung: ein Bogen, der aus
/// der Ecke unten rechts waechst.
private struct ResizeHandleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.maxX, y: rect.maxY), radius: rect.width / 2,
                   startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        return path
    }
}

/// Haengt `.onDrop` nur an, wenn `active` gilt - `RenderMode` laesst es weg
/// (siehe `EnvironmentValues.dashboardRendersForScreenshot`), das echte
/// Dashboard gibt immer `true`.
struct BentoDropTarget: ViewModifier {
    let editor: DashboardEditor
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.onDrop(of: [.plainText], delegate: BentoDropDelegate(editor: editor))
        } else {
            content
        }
    }
}

/// Ziel fuer Widgets, die aus der Galerie des Bearbeitungsmodus gezogen
/// werden (Payload `"apolloshell.widget:<WidgetKind.rawValue>"`,
/// `NSItemProvider(object:)` bei `.onDrag` in `EditGalleryView`). Laedt die
/// Nutzlast einmal beim Betreten (async, `NSItemProvider`) und haelt die Art danach
/// in `editor.draggedKind` fest, damit jede weitere Bewegung sofort eine
/// Vorschau zeigen kann.
struct BentoDropDelegate: DropDelegate {
    let editor: DashboardEditor

    func dropEntered(info: DropInfo) {
        // Zaehler jetzt gemerkt: kommt die Nutzlast erst an, nachdem der Zug
        // dieses Ziel schon verlassen hat (`dropExited` erhoeht ihn), gilt
        // das Ergebnis nicht mehr - sonst lebt der Ghost-Umriss wieder auf.
        let generation = editor.dropGeneration
        loadKind(info) { kind in
            guard generation == editor.dropGeneration else { return }
            editor.draggedKind = kind
            if let kind { updatePreview(kind, info: info) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let kind = editor.draggedKind {
            updatePreview(kind, info: info)
        }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        editor.dropGeneration += 1
        editor.dropPreview = nil
        editor.draggedKind = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let location = info.location
        if let kind = editor.draggedKind {
            add(kind, at: location)
            return true
        }
        // Noch nicht geladen (sehr kurzer Zug): nachreichen, aber nur, wenn
        // dieses Ziel inzwischen nicht verlassen wurde.
        let generation = editor.dropGeneration
        loadKind(info) { [self] kind in
            guard generation == editor.dropGeneration, let kind else { return }
            add(kind, at: location)
        }
        return true
    }

    private func add(_ kind: WidgetKind, at location: CGPoint) {
        let preview = editor.previewDrop(kind, x: location.x, y: location.y)
        editor.dropPreview = nil
        editor.draggedKind = nil
        guard let preview, preview.valid else { return }
        let places = WeatherFavorites.load(from: try? Data(contentsOf: ShellFiles.live.weather))
        editor.add(kind, frame: preview.frame, places: places)
    }

    private func updatePreview(_ kind: WidgetKind, info: DropInfo) {
        let preview = editor.previewDrop(kind, x: info.location.x, y: info.location.y)
        editor.dropPreview = preview.map { (frame: $0.frame, valid: $0.valid) }
    }

    private func loadKind(_ info: DropInfo, completion: @escaping @MainActor @Sendable (WidgetKind?) -> Void) {
        guard let provider = info.itemProviders(for: [.plainText]).first else {
            completion(nil)
            return
        }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            let kind = (value as? String).flatMap(BentoWidgetDragPayload.kind(from:))
            DispatchQueue.main.async { completion(kind) }
        }
    }
}
