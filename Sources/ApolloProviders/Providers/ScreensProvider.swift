import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class ScreensProvider: BaseProvider {
    private let source: any ScreensSource
    private var lastLayout: [Value]?

    public init(source: any ScreensSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("screens"), clock: clock)
    }

    override func didStart() {
        lastLayout = nil
        source.observeChanges { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    override func didStop() {
        source.stopObserving()
    }

    private func refresh() {
        guard isRunning else { return }
        let screens = source.screens()
        let records = screens.enumerated().map { Self.record($0.element, index: $0.offset + 1) }
        let list = Value.list(records)
        publish("list", list)
        let main = screens.firstIndex { $0.primary } ?? (screens.isEmpty ? nil : 0)
        publish("main", main.map { records[$0] } ?? .record(Record()))
        let layout = screens.enumerated().map { entry -> Value in
            var copy = entry.element
            copy.fullscreen = false
            return Self.record(copy, index: entry.offset + 1)
        }
        if let lastLayout, lastLayout != layout {
            emit("screens.changed", Record([("screens", list)]))
        }
        lastLayout = layout
    }

    public static func key(_ screen: ScreenState) -> String {
        ScreenInfo.key(name: screen.name, frame: screen.frame)
    }

    public static func record(_ screen: ScreenState, index: Int) -> Value {
        .record(Record([
            ("id", .string(key(screen))),
            ("name", .string(screen.name)),
            ("main", .bool(screen.primary)),
            ("index", .number(Double(index))),
            ("x", ProviderValue.number(Double(screen.frame.minX))),
            ("y", ProviderValue.number(Double(screen.frame.minY))),
            ("width", ProviderValue.number(Double(screen.frame.width))),
            ("height", ProviderValue.number(Double(screen.frame.height))),
            ("visible-x", ProviderValue.number(Double(screen.visibleFrame.minX))),
            ("visible-y", ProviderValue.number(Double(screen.visibleFrame.minY))),
            ("visible-width", ProviderValue.number(Double(screen.visibleFrame.width))),
            ("visible-height", ProviderValue.number(Double(screen.visibleFrame.height))),
            ("scale", ProviderValue.number(screen.scale)),
            ("notch", .bool(screen.notch)),
            ("menubar-height", ProviderValue.number(screen.menubarHeight)),
            ("fullscreen", .bool(screen.fullscreen)),
            ("notch-left", area(screen.notchLeft, in: screen.frame)),
            ("notch-right", area(screen.notchRight, in: screen.frame)),
        ]))
    }

    public static func area(_ rect: CGRect?, in frame: CGRect) -> Value {
        guard let rect else { return .null }
        return .record(Record([
            ("x", .number(Double(rect.minX - frame.minX))),
            ("y", .number(Double(frame.maxY - rect.maxY))),
            ("width", .number(Double(rect.width))),
            ("height", .number(Double(rect.height))),
        ]))
    }
}
