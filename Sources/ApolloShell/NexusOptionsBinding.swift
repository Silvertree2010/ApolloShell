import SwiftUI

/// Bindung an die Optionen eines Eintrags: lesen ueber den Zugriff der Art
/// (z. B. `\.clock`), schreiben als neuer Baustein derselben Art - wie
/// `NexusBarOptions.binding` und `NexusDashboardCardOptions.binding` es beide
/// bauten. `get`/`set` holen bzw. schreiben den ganzen Baustein (Leiste: nach
/// Kennung; Dashboard: nach Karten-Art), `read`/`make` greifen dessen
/// Optionen heraus bzw. bauen ihn mit neuen Optionen neu auf.
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
