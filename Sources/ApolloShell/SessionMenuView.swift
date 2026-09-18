import ApolloShellCore
import SwiftUI

/// Knopfspalte des Sitzungsmenues: Abmelden, Ausschalten, Emblem,
/// Ruhezustand, Neustart - wie Caelestia, in Apple-Optik.
struct SessionMenuView: View {
    @Bindable var model: SessionMenuModel
    @FocusState private var focused: Bool
    @Environment(\.shellStyle) private var style

    /// Bringt das Theme ein eigenes Emblem mit?
    private var emblemFromTheme: Bool {
        style.iconFile("session-emblem") != nil
    }

    var body: some View {
        VStack(spacing: SessionMenu.spacing) {
            ForEach(Array(SessionAction.menuOrder.enumerated()), id: \.element) { index, action in
                if index == SessionAction.emblemSlot {
                    // Weicher Uebergang statt Sprung in die neue Bewegung:
                    // neue Identitaet pro Reaktion, die alte blendet in
                    // 0,18 s aus.
                    ZStack {
                        // Bringt das Theme `icons/session-emblem.png` mit,
                        // steht dort dieses Bild statt des gezeichneten
                        // Planeten - das Maskottchen gehoert damit ins Theme.
                        if emblemFromTheme {
                            ThemedIcon("session-emblem")
                                .frame(width: SessionMenu.buttonSize, height: SessionMenu.buttonSize)
                        } else {
                            SessionEmblem(
                                timeline: model.emblem,
                                size: SessionMenu.buttonSize,
                                animating: model.isVisible,
                                fixedTime: model.fixedTime
                            )
                            .id(model.emblem.reaction)
                            .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                        }
                    }
                    .frame(width: SessionMenu.buttonSize, height: SessionMenu.buttonSize)
                    .accessibilityHidden(true)
                }
                // Ueberfahren ist NICHT Auswaehlen: nur ein kurzer Schimmer,
                // solange die Maus drauf ist (wie Caelestias StateLayer). Die
                // farbige Auswahl gehoert der Tastatur. Die erste Fassung
                // waehlte beim Ueberfahren aus, und die Fuellung blieb stehen.
                SessionButton(
                    action: action,
                    selected: model.selection.action == action,
                    hovered: model.hovered == action
                ) {
                    model.perform(action)
                }
                .background(HoverTracker { model.hover(action, inside: $0) })
            }
        }
        .padding(.vertical, SessionMenu.padding)
        .padding(.leading, SessionMenu.padding)
        // Rechts nur der schmale Kantenabstand; der Teil des Fensters, der
        // ueber den Bildschirmrand ragt, liegt ausserhalb dieser Ansicht.
        .padding(.trailing, SessionMenu.edgePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.upArrow) { model.move(by: -1); return .handled }
        .onKeyPress(.downArrow) { model.move(by: 1); return .handled }
        .onKeyPress(.return) { model.performSelected(); return .handled }
        .onExitCommand { model.onClose() }
        .onChange(of: model.openCount, initial: true) { focused = true }
    }
}

/// Ein Knopf: 80 x 80, Ecken wie bei Caelestia 20 normal, 28 ausgewaehlt,
/// 12 gedrueckt, Wechsel in 200 ms.
private struct SessionButton: View {
    let action: SessionAction
    let selected: Bool
    let hovered: Bool
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            // Mit `icons/session-shutdown.png` und den drei Geschwistern
            // tauscht ein Theme diese Knoepfe aus.
            // Das Bild aus dem Theme so gross wie das Zeichen, das es
            // ersetzt - sonst fuellt es den ganzen Knopf und wirkt neben den
            // eingebauten Symbolen zu wuchtig.
            ThemedIcon(action.iconID, fallback: action.symbolName)
                .font(.system(size: 28, weight: .medium))
                .frame(width: 30, height: 30)
                .frame(width: SessionMenu.buttonSize, height: SessionMenu.buttonSize)
        }
        .buttonStyle(SessionButtonStyle(selected: selected, hovered: hovered))
        .help(action.title)
        .accessibilityLabel(action.title)
    }
}

private struct SessionButtonStyle: ButtonStyle {
    let selected: Bool
    let hovered: Bool
    @Environment(\.shellStyle) private var style

    func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = configuration.isPressed ? 12 : (selected ? 28 : 20)
        configuration.label
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                selected ? AnyShapeStyle(style.accent.opacity(0.85)) : AnyShapeStyle(Color.primary.opacity(0.08)),
                in: .rect(cornerRadius: radius)
            )
            // Hover-Schimmer: 8 % obendrauf, wie Caelestias StateLayer.
            .overlay(Color.primary.opacity(hovered ? 0.08 : 0), in: .rect(cornerRadius: radius))
            .contentShape(.rect(cornerRadius: radius))
            // Caelestia: Standardkurve cubic-bezier(0.2, 0, 0, 1), 200 ms.
            .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.2), value: radius)
            .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.2), value: selected)
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
