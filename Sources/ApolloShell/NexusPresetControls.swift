import ApolloShellCore
import SwiftUI

// The template prompt the way Nexus > Bar, Nexus > Quick Actions and
// Nexus > Dashboard each had it on their own: a menu "Load template ...", a
// "Reset" button (grey when the level matches the default already) and an
// alert that asks once more before the current level disappears. The texts of
// the prompt stay with the callers, because their wording differs
// (bar/panel/dashboard); only the mechanics are here.
//

// Two separate pieces instead of one whole: the three editors line them up
// differently (the bar and the dashboard right next to each other, the quick
// actions with a spacer in between) - that stays with the callers.
// Aufrufern.

/// "Load template ...". Reports the choice only through `onSelect` - whether
/// `pending` comes of it (the prompt through `nexusPresetAlert`) or the choice
/// is handed on right away (`NexusDashboardCardSections`, where the page holds
/// the prompt) is decided by the caller.
struct NexusPresetMenu<P: LayoutPreset>: View {
    let onSelect: (P) -> Void

    var body: some View {
        Menu("Vorlage laden …") {
            ForEach(Array(P.allCases)) { preset in
                Button(preset.title) { onSelect(preset) }
            }
        }
        .fixedSize()
    }
}

/// "Reset", grey when the level matches the default already.
struct NexusPresetResetButton<P: LayoutPreset>: View {
    let layout: P.Layout
    let action: () -> Void

    var body: some View {
        Button("Reset", action: action)
            .disabled(layout == P.default.layout)
    }
}

extension View {
    /// The prompt itself: "Load template X?" or "... reset?", with
    /// Load/Reset and Cancel. `title`/`message` is delivered by the caller,
    /// because the wording differs per level; `onConfirm` gets the finished
    /// level.
    func nexusPresetAlert<P: LayoutPreset>(
        _ pending: Binding<LayoutPresetReplacement<P>?>,
        title: (LayoutPresetReplacement<P>) -> String,
        message: (LayoutPresetReplacement<P>) -> String,
        onConfirm: @escaping (P.Layout) -> Void
    ) -> some View {
        let isPresented = Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } })
        return alert(pending.wrappedValue.map(title) ?? "", isPresented: isPresented, presenting: pending.wrappedValue) { replacement in
            Button(replacement.confirmLabel) {
                onConfirm(replacement.layout)
                pending.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: { replacement in
            Text(message(replacement))
        }
    }
}
