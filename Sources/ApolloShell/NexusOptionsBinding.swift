import SwiftUI

/// Binding to the options of an entry: read via the access of the kind
/// (e.g. `\.clock`), write as a new widget of the same kind - as
/// `NexusBarOptions.binding` and `NexusDashboardCardOptions.binding` both
/// built it. `get`/`set` fetch resp. write the whole widget (bar: by
/// identifier; dashboard: by card kind), `read`/`make` pull its
/// options out resp. rebuild it with new options.
@MainActor
func nexusOptionsBinding<Module, T: Sendable>(
    get: @escaping @MainActor () -> Module?,
    set: @escaping @MainActor (Module) -> Void,
    read: @escaping @Sendable (Module) -> T?,
    make: @escaping @Sendable (T) -> Module,
    fallback: T
) -> Binding<T> {
    Binding(
        get: { get().flatMap(read) ?? fallback },
        set: { set(make($0)) }
    )
}
