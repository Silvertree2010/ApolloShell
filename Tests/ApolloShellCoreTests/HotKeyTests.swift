import ApolloShellCore
import Carbon.HIToolbox
import Foundation
import Testing

@Suite("Global keyboard shortcuts")
struct HotKeyTests {
    @Test("special keys are bit-identical to Carbon", arguments: [
        (HotKeyModifiers.command, cmdKey), (HotKeyModifiers.shift, shiftKey),
        (HotKeyModifiers.option, optionKey), (HotKeyModifiers.control, controlKey),
    ])
    func carbonBits(flag: HotKeyModifiers, carbon: Int) {
        #expect(flag.rawValue == UInt32(carbon))
    }

    @Test("key codes are Carbon's kVK values", arguments: [
        (HotKeyKey.space, kVK_Space), (HotKeyKey.escape, kVK_Escape), (HotKeyKey.delete, kVK_Delete),
        (HotKeyKey.forwardDelete, kVK_ForwardDelete), (HotKeyKey.d, kVK_ANSI_D), (HotKeyKey.u, kVK_ANSI_U),
        (HotKeyKey.comma, kVK_ANSI_Comma), (HotKeyKey.f20, kVK_F20),
    ])
    func keyConstants(ours: UInt32, carbon: Int) {
        #expect(ours == UInt32(carbon))
    }

    @Test("label per key code", arguments: [
        (kVK_ANSI_D, "D"), (kVK_ANSI_U, "U"), (kVK_ANSI_Z, "Z"), (kVK_ANSI_Y, "Y"), (kVK_ANSI_Comma, ","),
        (kVK_ANSI_0, "0"), (kVK_ANSI_Grave, "`"), (kVK_ISO_Section, "§"), (kVK_Space, "Space"),
        (kVK_Return, "↩"), (kVK_Tab, "⇥"), (kVK_Escape, "⎋"), (kVK_Delete, "⌫"), (kVK_UpArrow, "↑"),
        (kVK_LeftArrow, "←"), (kVK_PageDown, "⇟"), (kVK_ANSI_Keypad9, "Num 9"), (kVK_F1, "F1"),
        (kVK_F5, "F5"), (kVK_F13, "F13"), (kVK_F19, "F19"), (kVK_F20, "F20"),
    ])
    func keyNames(code: Int, name: String) {
        #expect(HotKeyKey.name(for: UInt32(code)) == name)
    }

    @Test("character keys ask the layout for their mapping, others don't", arguments: [
        (kVK_ANSI_D, true), (kVK_ANSI_Comma, true), (kVK_ANSI_1, true), (kVK_Space, false),
        (kVK_F20, false), (kVK_Return, false), (kVK_ANSI_Keypad1, false),
    ])
    func characterKeys(code: Int, isCharacter: Bool) {
        #expect(HotKeyKey.isCharacterKey(UInt32(code)) == isCharacter)
    }

    @Test("display like in Apple's menus", arguments: [
        (HotKey(keyCode: HotKeyKey.space, modifiers: .option), "⌥Space"),
        (HotKey(keyCode: HotKeyKey.d, modifiers: .hyper), "⌃⌥⇧⌘D"),
        (HotKey(keyCode: HotKeyKey.f20), "F20"),
        (HotKey(keyCode: HotKeyKey.comma, modifiers: [.command, .shift]), "⇧⌘,"),
        (HotKey(keyCode: HotKeyKey.u, modifiers: [.command, .control]), "⌃⌘U"),
        (HotKey(keyCode: 0x7F, modifiers: .command), "⌘Key 127"),
    ])
    func display(key: HotKey, text: String) {
        #expect(key.display() == text)
    }

    @Test("The character of the current layout replaces the US label", arguments: [
        (HotKey(keyCode: UInt32(kVK_ANSI_Z), modifiers: .command), "Y", "⌘Y"),
        (HotKey(keyCode: UInt32(kVK_ANSI_Semicolon), modifiers: [.control, .option]), "Ö", "⌃⌥Ö"),
    ])
    func displayWithLayout(key: HotKey, keyName: String, text: String) {
        #expect(key.display(keyName: keyName) == text)
    }

    @Test("defaults for fresh installations", arguments: [
        (HotKeyAction.launcher, "⌥Space"), (HotKeyAction.dashboard, "⌃⌥D"),
        (HotKeyAction.utilities, "⌃⌥U"), (HotKeyAction.nexus, "⌃⌥,"),
    ])
    func firstLaunchDefaults(action: HotKeyAction, text: String) {
        #expect(HotKeySettings.firstLaunch[action]?.display() == text)
    }

    @Test("existing installation keeps F20 and Hyper", arguments: [
        (HotKeyAction.launcher, "F20"), (HotKeyAction.dashboard, "⌃⌥⇧⌘D"),
        (HotKeyAction.utilities, "⌃⌥⇧⌘U"), (HotKeyAction.nexus, "⌃⌥⇧⌘,"),
    ])
    func existingDefaults(action: HotKeyAction, text: String) {
        #expect(HotKeySettings.existingInstall[action]?.display() == text)
    }

    @Test("new defaults: no duplicates, no warning", arguments: HotKeyAction.allCases)
    func firstLaunchConflictFree(action: HotKeyAction) throws {
        let key = try #require(HotKeySettings.firstLaunch[action])
        #expect(HotKeySettings.firstLaunch.action(using: key, except: action) == nil)
        #expect(HotKeyAdvice.warning(for: key) == nil)
    }

    @Test("migration: which shortcuts from which file", arguments: [
        (nil, HotKeySettings.firstLaunch),
        ("{}", HotKeySettings.existingInstall),
        (#"{"bar":{"showClock":false},"toasts":{}}"#, HotKeySettings.existingInstall),
        ("broken", HotKeySettings.existingInstall),
        (#"{"hotKeys":"no"}"#, HotKeySettings.existingInstall),
        (#"{"hotKeys":{}}"#, HotKeySettings.firstLaunch),
        (#"{"hotKeys":{"launcher":null}}"#,
         HotKeySettings(dashboard: HotKeySettings.firstLaunch.dashboard, utilities: HotKeySettings.firstLaunch.utilities,
                        nexus: HotKeySettings.firstLaunch.nexus)),
        (#"{"hotKeys":{"launcher":{"keyCode":90,"modifiers":[]}}}"#,
         HotKeySettings(launcher: HotKey(keyCode: HotKeyKey.f20), dashboard: HotKeySettings.firstLaunch.dashboard,
                        utilities: HotKeySettings.firstLaunch.utilities, nexus: HotKeySettings.firstLaunch.nexus)),
        (#"{"hotKeys":{"launcher":{"keyCode":999}}}"#, HotKeySettings.firstLaunch),
        (#"{"hotKeys":{"launcher":{"keyCode":"D"}}}"#, HotKeySettings.firstLaunch),
        (#"{"hotKeys":{"nexus":{"keyCode":43,"modifiers":["command","hyper"]}}}"#,
         HotKeySettings(launcher: HotKeySettings.firstLaunch.launcher, dashboard: HotKeySettings.firstLaunch.dashboard,
                        utilities: HotKeySettings.firstLaunch.utilities,
                        nexus: HotKey(keyCode: HotKeyKey.comma, modifiers: .command))),
    ] as [(String?, HotKeySettings)])
    func migration(json: String?, expected: HotKeySettings) {
        #expect(ShellSettings.load(from: json.map { Data($0.utf8) }).hotKeys == expected)
    }

    @Test("writing and reading back, even without a shortcut", arguments: [
        HotKeySettings.firstLaunch, HotKeySettings.existingInstall, HotKeySettings(),
        HotKeySettings(launcher: HotKey(keyCode: HotKeyKey.space, modifiers: [.command, .shift])),
    ])
    func roundTrip(hotKeys: HotKeySettings) {
        var settings = ShellSettings.firstLaunch
        settings.hotKeys = hotKeys
        #expect(ShellSettings.load(from: settings.encoded()).hotKeys == hotKeys)
    }

    @Test("the file calls special keys by name", arguments: [
        "\"hotKeys\"", "\"launcher\"", "\"keyCode\"", "\"modifiers\"", "\"option\"", "\"control\"", "\"nexus\" : null",
    ])
    func readableFile(text: String) {
        var settings = ShellSettings.firstLaunch
        settings.hotKeys.nexus = nil
        #expect(String(decoding: settings.encoded(), as: UTF8.self).contains(text))
    }

    @Test("recording: what a keystroke does", arguments: [
        (kVK_Space, HotKeyModifiers.option, HotKeyRecording.record(HotKey(keyCode: HotKeyKey.space, modifiers: .option))),
        (kVK_Escape, HotKeyModifiers(), HotKeyRecording.cancel),
        (kVK_Delete, HotKeyModifiers(), HotKeyRecording.clear),
        (kVK_ForwardDelete, HotKeyModifiers(), HotKeyRecording.clear),
        (kVK_Escape, HotKeyModifiers.command, HotKeyRecording.record(HotKey(keyCode: HotKeyKey.escape, modifiers: .command))),
        (kVK_F20, HotKeyModifiers(), HotKeyRecording.record(HotKey(keyCode: HotKeyKey.f20))),
        (kVK_F5, HotKeyModifiers.shift, HotKeyRecording.record(HotKey(keyCode: UInt32(kVK_F5), modifiers: .shift))),
        (kVK_ANSI_D, HotKeyModifiers(), HotKeyRecording.rejected(.needsModifier)),
        (kVK_Space, HotKeyModifiers(), HotKeyRecording.rejected(.needsModifier)),
        (kVK_ANSI_D, HotKeyModifiers.shift, HotKeyRecording.rejected(.shiftOnly)),
        (kVK_ANSI_D, HotKeyModifiers([.shift, .command]),
         HotKeyRecording.record(HotKey(keyCode: HotKeyKey.d, modifiers: [.shift, .command]))),
    ])
    func recording(code: Int, modifiers: HotKeyModifiers, expected: HotKeyRecording) {
        #expect(HotKeyRecording.evaluate(keyCode: UInt32(code), modifiers: modifiers) == expected)
    }

    @Test("who already has a shortcut", arguments: [
        (HotKey(keyCode: HotKeyKey.d, modifiers: [.control, .option]), HotKeyAction.launcher, HotKeyAction.dashboard),
        (HotKey(keyCode: HotKeyKey.d, modifiers: [.control, .option]), HotKeyAction.dashboard, nil),
        (HotKey(keyCode: HotKeyKey.d, modifiers: .option), HotKeyAction.launcher, nil),
    ] as [(HotKey, HotKeyAction, HotKeyAction?)])
    func owner(key: HotKey, recordingFor: HotKeyAction, owner: HotKeyAction?) {
        #expect(HotKeySettings.firstLaunch.action(using: key, except: recordingFor) == owner)
    }

    @Test("Advice on tricky shortcuts", arguments: [
        (HotKey(keyCode: HotKeyKey.space, modifiers: .command), HotKeyWarning.system("Spotlight")),
        (HotKey(keyCode: HotKeyKey.d, modifiers: [.option, .command]), HotKeyWarning.system("Show and Hide the Dock")),
        (HotKey(keyCode: HotKeyKey.comma, modifiers: .command), HotKeyWarning.system("Settings, in Any App")),
        (HotKey(keyCode: HotKeyKey.u, modifiers: .option), HotKeyWarning.typesCharacters),
        (HotKey(keyCode: HotKeyKey.comma, modifiers: [.option, .shift]), HotKeyWarning.typesCharacters),
        (HotKey(keyCode: HotKeyKey.space, modifiers: .option), nil),
        (HotKey(keyCode: HotKeyKey.u, modifiers: [.control, .option]), nil),
        (HotKey(keyCode: UInt32(kVK_F5), modifiers: .option), nil),
        (HotKey(keyCode: HotKeyKey.f20), nil),
    ] as [(HotKey, HotKeyWarning?)])
    func advice(key: HotKey, warning: HotKeyWarning?) {
        #expect(HotKeyAdvice.warning(for: key) == warning)
    }

    @Test("Registration failed: says why", arguments: [
        (true, eventHotKeyExistsErr, "Another app"),
        (false, eventHotKeyInvalidErr, "error -9879"),
    ])
    func registrationText(taken: Bool, status: Int, fragment: String) {
        #expect(HotKeyText.registrationFailed(alreadyTaken: taken, status: Int32(status)).contains(fragment))    }
}
