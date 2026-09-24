import AppKit
import SwiftUI
import Observation
import ApolloBase

@MainActor
@Observable
final class ErrorOverlayModel {
    enum State: Equatable {
        case hidden
        case errors([Diagnostic])
        case badge(Int)
    }

    static let visibleLimit = 20
    static let badgeSeconds: TimeInterval = 8

    private(set) var state: State = .hidden
    private(set) var problems: [Diagnostic] = []
    @ObservationIgnored var schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
    }
    @ObservationIgnored var onChange: (State) -> Void = { _ in }
    @ObservationIgnored private var generation = 0

    func show(_ diagnostics: [Diagnostic]) {
        generation += 1
        problems = diagnostics
        let errors = diagnostics.filter { $0.severity == .error }
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        if !errors.isEmpty {
            set(.errors(diagnostics))
        } else if warnings > 0 {
            set(.badge(warnings))
            let current = generation
            schedule(Self.badgeSeconds) { [weak self] in
                guard let self, self.generation == current else { return }
                self.set(.hidden)
            }
        } else {
            set(.hidden)
        }
    }

    func add(_ diagnostic: Diagnostic) {
        guard !problems.contains(where: { $0.message == diagnostic.message && $0.span == diagnostic.span && $0.severity == diagnostic.severity }) else { return }
        show(problems + [diagnostic])
    }

    func dismiss() {
        generation += 1
        set(.hidden)
    }

    var warningCount: Int { problems.filter { $0.severity == .warning }.count }

    private func set(_ next: State) {
        guard next != state else { return }
        state = next
        onChange(next)
    }

    static func location(_ diagnostic: Diagnostic) -> String? {
        guard let span = diagnostic.span else { return nil }
        let name = URL(fileURLWithPath: span.file).lastPathComponent
        return "\(name):\(span.start.line):\(span.start.column)"
    }
}

struct ErrorOverlayView: View {
    let model: ErrorOverlayModel
    let open: (Diagnostic) -> Void
    let reload: () -> Void

    var body: some View {
        switch model.state {
        case .hidden:
            EmptyView()
        case .badge(let count):
            Label("\(count)", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
        case .errors(let diagnostics):
            VStack(alignment: .leading, spacing: 8) {
                Text("Config problems").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                            row(diagnostic)
                        }
                    }
                }
                .frame(maxHeight: CGFloat(min(diagnostics.count, ErrorOverlayModel.visibleLimit)) * 44)
                HStack {
                    Button("Open") { if let first = diagnostics.first(where: { $0.span != nil }) { open(first) } }
                    Button("Reload", action: reload)
                    Spacer()
                    Button("Dismiss") { model.dismiss() }
                }
            }
            .padding(14)
            .frame(width: 420, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    private func row(_ diagnostic: Diagnostic) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(diagnostic.severity == .error ? Color.red : Color.orange)
                if let location = ErrorOverlayModel.location(diagnostic) {
                    Text(location).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            Text(diagnostic.message).font(.callout)
            if let help = diagnostic.help {
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onTapGesture { open(diagnostic) }
    }
}

@MainActor
final class ErrorOverlayWindow {
    let model: ErrorOverlayModel
    private(set) var panel: ShellPanel?
    private var hosting: FirstMouseHostingView<ErrorOverlayView>?
    private let open: (Diagnostic) -> Void
    private let reload: () -> Void
    private let stage: any WindowStage
    private let visibleFrame: @MainActor () -> CGRect?

    init(model: ErrorOverlayModel, open: @escaping (Diagnostic) -> Void, reload: @escaping () -> Void,
         stage: any WindowStage = SystemStage.shared, visibleFrame: @escaping @MainActor () -> CGRect? = { NSScreen.screens.first?.visibleFrame }) {
        self.model = model
        self.open = open
        self.reload = reload
        self.stage = stage
        self.visibleFrame = visibleFrame
        model.onChange = { [weak self] _ in self?.update() }
    }

    var hostingView: NSView? { hosting }

    func update() {
        guard model.state != .hidden else {
            if let panel { stage.out(panel) }
            return
        }
        let panel = self.panel ?? makePanel()
        guard let hosting else { return }
        hosting.rootView = makeView()
        resize()
        stage.front(panel, key: false)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.resize() }
        }
    }

    private func makeView() -> ErrorOverlayView {
        ErrorOverlayView(model: model, open: open, reload: reload)
    }

    private func resize() {
        guard model.state != .hidden, let panel, let hosting, let visible = visibleFrame() else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let frame = CGRect(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 12, width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private func makePanel() -> ShellPanel {
        let panel = ShellPanel(level: SurfaceWindowKind.level("overlay", kind: "overlay"),
                               behavior: [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary])
        let hosting = FirstMouseHostingView(rootView: makeView())
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
        return panel
    }
}
