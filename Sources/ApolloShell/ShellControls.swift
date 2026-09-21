import AppKit
import SwiftUI

// Building blocks that outlived the Nexus window: the introduction, the
// shortcuts window and the edit mode's popovers use them.

/// A colored tile with a white symbol, like the page symbols of System
/// Settings.
struct SymbolTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// A switch with a title and a grey subtitle (Caelestia: ToggleRow with
/// text/subtext). Always as a switch, never as a checkbox.
struct SettingToggle: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
            if let subtitle { Text(subtitle) }
        }
        .toggleStyle(.switch)
    }
}

/// A search row in the form: a magnifier, a plain field, a clear button.
struct PlainSearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    var busy = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
            if busy {
                ProgressView()
                    .controlSize(.small)
            } else if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Clear Search")
            }
        }
    }
}

/// Jumps into System Settings.
///
/// The area ids are the bundle IDs of the settings extensions in
/// /System/Library/ExtensionKit/Extensions (measured 14.09., macOS 26.6).
/// Without an area the app is opened through its bundle ID: that works for
/// sure, no matter what it is called after updates or where it lies.
enum SystemSettings {
    enum Pane: String {
        case wallpaper = "com.apple.Wallpaper-Settings.extension"
        case appearance = "com.apple.Appearance-Settings.extension"
        case network = "com.apple.Network-Settings.extension"
        case bluetooth = "com.apple.BluetoothSettings"
        case sound = "com.apple.Sound-Settings.extension"
        case notifications = "com.apple.Notifications-Settings.extension"
        case softwareUpdate = "com.apple.Software-Update-Settings.extension"
        case language = "com.apple.Localization-Settings.extension"
        case about = "com.apple.SystemProfiler.AboutExtension"
        /// Privacy & Security > Accessibility (the anchor out of the search
        /// terms of the extension, measured 14.09., macOS 26.6).
        case accessibility = "com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
    }

    static func open(_ pane: Pane?) {
        if let pane, let url = URL(string: "x-apple.systempreferences:\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
            return
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }
}

/// An ordinary window that knows the usual editing shortcuts itself.
///
/// The app has no menu bar (accessory). Cmd+C/V/X/A/Z and Cmd+W run through
/// the menu entries in macOS though - without a menu, Cmd+V would do nothing
/// in the search field. Instead of an invisible main menu for the whole app
/// (which would take in the launcher and the panels too), only this window
/// does it: the same actions up the responder chain. Cmd+Q on purpose not -
/// that would end the whole shell, bar and all.
final class ShellWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift],
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return false }
        let shift = flags.contains(.shift)
        let action: Selector? = switch (key, shift) {
        case ("w", false): #selector(NSWindow.performClose(_:))
        case ("x", false): #selector(NSText.cut(_:))
        case ("c", false): #selector(NSText.copy(_:))
        case ("v", false): #selector(NSText.paste(_:))
        case ("a", false): #selector(NSText.selectAll(_:))
        case ("z", false): Selector(("undo:"))
        case ("z", true): Selector(("redo:"))
        default: nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }
}
