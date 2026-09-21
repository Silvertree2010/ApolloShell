import AppKit
import ApolloShellCore
import SwiftUI

/// The keyboard shortcuts in a window of their own
/// (design/2026-09-21-menubar-nexus.md, task 3).
///
/// A menu cannot record keys: the recorder needs a key window. Everything
/// else about the shell sits in the menu bar item. Opened from there
/// ("Shortcuts…"); one window, opening it again brings it forward, closing
/// hands the focus back to the app that had it.
@MainActor
final class ShortcutsWindow: NSObject, NSWindowDelegate {
    private static let size = NSSize(width: 520, height: 470)

    private let settings: ShellSettingsStore
    private let hotKeys: HotKeyCenter
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?

    init(settings: ShellSettingsStore, hotKeys: HotKeyCenter) {
        self.settings = settings
        self.hotKeys = hotKeys
        super.init()
    }

    func show() {
        let window = self.window ?? makeWindow()
        if !window.isVisible {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        // NexusWindow: knows ⌘W without a menu bar.
        let window = NexusWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = String(localized: "Shortcuts")
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        let view = ShortcutsView(store: settings, center: hotKeys)
        window.contentViewController = NSHostingController(rootView: view.shellTheme())
        window.setContentSize(Self.size)
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        hotKeys.cancelRecording()
        previousApp?.activate()
        previousApp = nil
    }
}

/// The four recorders, the note about ⎋ and ⌫, and the two presets.
struct ShortcutsView: View {
    @Bindable var store: ShellSettingsStore
    let center: HotKeyCenter

    var body: some View {
        Form {
            Section {
                ForEach(HotKeyAction.allCases) { action in
                    HotKeyRow(center: center, store: store, action: action)
                }
            } footer: {
                Text("Apply in any app, immediately. To change, click the field and press the new combination – ⎋ cancels, ⌫ removes the shortcut. Spotlight stays on ⌘Space.")
            }
            Section {
                ForEach(ShortcutPreset.allCases) { preset in
                    LabeledContent {
                        Button("Use") { store.settings.hotKeys = preset.settings }
                            .controlSize(.small)
                    } label: {
                        Text(preset.title)
                        Text(Self.summary(preset.settings))
                    }
                }
                LabeledContent {
                    Button("Clear") { store.settings.hotKeys = .firstLaunch }
                        .controlSize(.small)
                } label: {
                    Text("None")
                    Text("Everything through the menu bar")
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("“Launcher on fn” fits keyboard tools like Karabiner-Elements that turn a tapped fn into F20, or a held key into ⌃⌥⇧⌘.")
            }
            if store.saveFailed {
                Section {
                    Label("settings.json could not be saved. The change only applies until the next restart.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { center.cancelRecording() }
    }

    static func summary(_ hotKeys: HotKeySettings) -> String {
        HotKeyAction.allCases.compactMap { hotKeys[$0].map(HotKeyKeyboard.display) }.joined(separator: ", ")
    }
}

/// The two sets the window offers, named after what they are.
enum ShortcutPreset: CaseIterable, Identifiable {
    case controlOption
    case fnKey

    var id: Self { self }

    var title: String {
        switch self {
        case .controlOption: String(localized: "Control and Option")
        case .fnKey: String(localized: "Launcher on fn")
        }
    }

    var settings: HotKeySettings {
        switch self {
        case .controlOption: .suggested
        case .fnKey: .existingInstall
        }
    }
}
