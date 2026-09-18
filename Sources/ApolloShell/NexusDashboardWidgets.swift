import ApolloShellCore
import SwiftUI

// Nexus > Dashboard, Bearbeiten > "Widgets" (design/2026-09-18-bento-plan-
// edit.md Task 4, mittlere Spalte): jede Art, die ins Dashboard gehoert, zum
// Ziehen auf die Seite. Die Nutzlast ist ein einfacher String
// (`BentoWidgetDragPayload`, `BentoEditOverlay.swift`); `BentoDropDelegate`
// liest ihn wieder aus.

/// Liste aller Widget-Arten zum Ziehen ins Dashboard. `showsAll`: auch Arten
/// ausserhalb der Heimat "Dashboard" (heute keine - der Schalter bleibt fuer
/// spaetere Flaechen, siehe `WidgetKind.home`).
struct NexusDashboardWidgetsSection: View {
    @State private var showsAll = false

    private var kinds: [WidgetKind] {
        WidgetKind.allCases.filter { showsAll || $0.home == .dashboard }
    }

    var body: some View {
        Section {
            Text("In das Dashboard ziehen.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(kinds) { kind in
                NexusDashboardWidgetRow(kind: kind)
            }
        } header: {
            Text("Widgets")
        } footer: {
            Toggle("Alle Widgets zeigen (erweitert)", isOn: $showsAll)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct NexusDashboardWidgetRow: View {
    let kind: WidgetKind

    var body: some View {
        HStack(spacing: 10) {
            NexusTile(symbol: kind.symbol, tint: .indigo, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                Text(String(localized: "\(kind.sizes.count) Größen"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "hand.draw")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .onDrag {
            NSItemProvider(object: BentoWidgetDragPayload.string(for: kind) as NSString)
        }
        .accessibilityLabel("\(kind.title) auf die Seite ziehen")
    }
}
