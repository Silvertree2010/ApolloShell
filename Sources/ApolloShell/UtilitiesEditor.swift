import ApolloShellCore
import SwiftUI

// MARK: - Keep Awake (Nexus > General)

/// “Keep Awake with the lid closed” - earlier on Nexus > Quick Actions, since
/// the global edit mode on Nexus > General (the quick actions page had only
/// this switch left). Deliberately not in the popover of the card in the edit
/// mode: the switch puts down a system rule with an administrator prompt right
/// away and could not be taken back with “Cancel”.
struct NexusKeepAwakeSection: View {
    @Bindable var store: ShellSettingsStore
    /// Does the rule without a password for the lid part lie on this Mac?
    @State private var lidRuleInstalled = false
    @State private var removingLidRule = false

    /// The lid part needs root (pmset disablesleep). On the first switch-on
    /// macOS asks once for an administrator and puts down the rule without a
    /// password while doing so - one should be able to read that beforehand,
    /// and one should be able to get rid of it here again.
    var body: some View {
        Section {
            NexusToggle(title: "Also With the Lid Closed",
                        subtitle: "While “Keep Awake” is on, the Mac won't sleep even with the lid closed",
                        isOn: $store.settings.keepAwake.lidClosed)
            if lidRuleInstalled {
                LabeledContent {
                    Button("Remove…") { removeLidRule() }
                        .disabled(removingLidRule)
                } label: {
                    Text("Password-Free Rule")
                    Text("Allows only switching this sleep setting without a password")
                }
            }
        } header: {
            Text("Keep Awake")
        } footer: {
            Text("Needs administrator rights once: the first time you turn it on, macOS asks for your password and ApolloShell adds a rule that allows only switching this sleep setting without a password. After that, nothing asks again. Declining leaves “Keep Awake” working only with the lid open. On battery it ends on its own at \(LidAwake.batteryFloor)%.")
        }
        // The rule comes about in the background as soon as the prompt is
        // answered; while the page is open, look every 2 s (one stat).
        .task {
            while !Task.isCancelled {
                lidRuleInstalled = LidAwakeRule.isInstalled
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func removeLidRule() {
        removingLidRule = true
        LidAwakeRule.remove { _ in
            removingLidRule = false
            lidRuleInstalled = LidAwakeRule.isInstalled
        }
    }
}

// MARK: - Preview model

/// A fixed model that reads nothing and switches nothing - up to task 7 for
/// `UtilitiesEditorPreview` (Nexus, removed), since then for the cards while
/// editing in the control centre panel itself (`UtilitiesEditOverlay.swift`:
/// `KeepAwakeCard`/`UtilitiesAudioCard` with the controls switched off).
/// Neutral sample devices.
@MainActor
enum UtilitiesEditorPreviewModel {
    static let model = UtilitiesModel.preview(
        keepAwakeSince: nil, wifiOn: true, micMuted: false, bluetoothOn: true, darkMode: true, nightShift: false,
        volume: 0.6,
        audioDevices: [
            UtilitiesAudioDevice(id: 1, name: "Lautsprecher", outputStreams: 1, inputStreams: 0,
                                 canBeDefaultOutput: true, canBeDefaultInput: false, hidden: false),
            UtilitiesAudioDevice(id: 2, name: "Mikrofon", outputStreams: 0, inputStreams: 1,
                                 canBeDefaultOutput: false, canBeDefaultInput: true, hidden: false),
        ],
        defaultOutput: 1, defaultInput: 2
    )
}

// MARK: - Texts and colors

/// The name, the glyph and the color of a button - for the gallery
/// (`EditGallery.swift`) and the editing area of the control centre
/// (`UtilitiesEditOverlay.swift`). Up to task 7 it was needed for Nexus' old
/// kit as well (the grid, the options, the template prompt) - that is gone now.
@MainActor
enum UtilitiesEditorText {
    /// The name in the grid: its own title, otherwise the app name, the address
    /// or the name of the shortcut, otherwise the name of the kind.
    static func title(_ entry: UtilitiesToggleEntry) -> String {
        let own: String? = switch entry.toggle {
        case .openApp(let o): nonEmpty(o.title) ?? BarApps.info(for: o.bundleID)?.name
        case .openLink(let o): nonEmpty(o.title) ?? UtilitiesLink.url(from: o.url).map(UtilitiesLink.displayText)
        case .runShortcut(let o): nonEmpty(o.title) ?? nonEmpty(o.name)
        default: nil
        }
        return own ?? entry.kind.title
    }

    /// The same glyph as in the panel, without a state (Wi-Fi always "wifi").
    static func icon(_ entry: UtilitiesToggleEntry) -> UtilitiesToggleItem.Icon {
        let look: QuickToggleLook = switch entry.toggle {
        case .openApp(let o): QuickToggles.openApp(o, appName: BarApps.info(for: o.bundleID)?.name)
        case .openLink(let o): QuickToggles.openLink(o)
        case .runShortcut(let o): QuickToggles.runShortcut(o)
        default: QuickToggleLook(symbol: entry.kind.symbol, active: false, enabled: true, help: "")
        }
        return UtilitiesToggleItem.icon(for: entry.toggle, look: look)
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension UtilitiesToggleGroup {
    /// The tile color in the gallery and in the options popover.
    var tint: Color {
        switch self {
        case .switches: .blue
        case .actions: .indigo
        case .custom: .orange
        }
    }
}

/// A colored tile like `NexusTile`, but with the glyph of the button (the
/// Bluetooth rune and the app symbol too) - in the options popover
/// (`UtilitiesEditOverlay.swift`). Up to task 7 it was needed in Nexus' old
/// grid and its gallery as well.
struct UtilitiesEditorGlyphTile: View {
    let icon: UtilitiesToggleItem.Icon
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        if case .app = icon {
            UtilitiesToggleGlyph(icon: icon, scale: size / 28)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(tint.gradient)
                .frame(width: size, height: size)
                .overlay {
                    UtilitiesToggleGlyph(icon: icon, scale: size / 34)
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
        }
    }
}
