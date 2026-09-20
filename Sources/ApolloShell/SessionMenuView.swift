import ApolloShellCore
import SwiftUI

/// The button column of the session menu: log out, shut down, the emblem,
/// sleep, restart - as in Caelestia, in an Apple look.
struct SessionMenuView: View {
    @Bindable var model: SessionMenuModel
    @FocusState private var focused: Bool
    @Environment(\.shellStyle) private var style

    /// Does the theme bring an emblem of its own?
    private var emblemFromTheme: Bool {
        style.iconFile("session-emblem") != nil
    }

    var body: some View {
        VStack(spacing: SessionMenu.spacing) {
            ForEach(Array(SessionAction.menuOrder.enumerated()), id: \.element) { index, action in
                if index == SessionAction.emblemSlot {
                    // A soft transition instead of a jump into the new motion:
                    // a new identity per reaction, and the old one fades out in
                    // 0.18 s.
                    ZStack {
                        // When the theme brings `icons/session-emblem.png`,
                        // that image stands there instead of the drawn planet -
                        // so the mascot belongs in the theme.
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
                // Hovering is NOT selecting: only a short shimmer while the
                // mouse is on it (like Caelestia's StateLayer). The colored
                // selection belongs to the keyboard. The first version selected
                // on hover, and the fill stayed standing.
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
        // On the right only the narrow edge gap; the part of the window that
        // sticks out over the screen edge lies outside this view.
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

/// One button: 80 x 80, the corners as in Caelestia 20 normally, 28 when
/// selected, 12 when pressed, the change in 200 ms.
private struct SessionButton: View {
    let action: SessionAction
    let selected: Bool
    let hovered: Bool
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            // With `icons/session-shutdown.png` and its three siblings a theme
            // swaps these buttons out.
            // The image out of the theme as big as the glyph it replaces -
            // otherwise it fills the whole button and looks too bulky next to
            // the built-in symbols.
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
            // The hover shimmer: 8 % on top, like Caelestia's StateLayer.
            .overlay(Color.primary.opacity(hovered ? 0.08 : 0), in: .rect(cornerRadius: radius))
            .contentShape(.rect(cornerRadius: radius))
            // Caelestia: the standard curve cubic-bezier(0.2, 0, 0, 1), 200 ms.
            .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.2), value: radius)
            .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.2), value: selected)
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
