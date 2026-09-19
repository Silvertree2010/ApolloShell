import ApolloShellCore
import SwiftUI

// Die Vorlagen-Rueckfrage, wie sie Nexus > Leiste, Nexus > Schnellaktionen
// und Nexus > Dashboard je fuer sich hatten: ein Menue "Vorlage laden ...",
// ein "Zuruecksetzen"-Knopf (grau, wenn die Ebene schon der Vorgabe
// entspricht) und ein Alert, der noch einmal fragt, bevor die jetzige Ebene
// verschwindet. Die Texte der Rueckfrage bleiben bei den Aufrufern, weil sich
// ihre Formulierungen unterscheiden (Leiste/Panel/Dashboard); hier nur die
// Mechanik.

// Zwei einzelne Stuecke statt eines Ganzen: die drei Editoren reihen sie
// unterschiedlich auf (die Leiste und das Dashboard direkt nebeneinander,
// die Schnellaktionen mit einem Spacer dazwischen) - das bleibt so bei den
// Aufrufern.

/// "Vorlage laden ...". Meldet die Wahl nur ueber `onSelect` - ob daraus
/// `pending` wird (Rueckfrage per `nexusPresetAlert`) oder die Wahl gleich
/// weitergereicht wird (`NexusDashboardCardSections`, die Rueckfrage haelt
/// dort die Seite), entscheidet der Aufrufer.
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

/// "Zuruecksetzen", grau, wenn die Ebene schon der Vorgabe entspricht.
struct NexusPresetResetButton<P: LayoutPreset>: View {
    let layout: P.Layout
    let action: () -> Void

    var body: some View {
        Button("Reset", action: action)
            .disabled(layout == P.default.layout)
    }
}

extension View {
    /// Die Rueckfrage selbst: "Vorlage X laden?" bzw. "... zuruecksetzen?",
    /// mit Laden/Zuruecksetzen und Abbrechen. `title`/`message` liefert der
    /// Aufrufer, weil der Wortlaut sich je Ebene unterscheidet; `onConfirm`
    /// bekommt die fertige Ebene.
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
