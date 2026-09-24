import AppKit
import ApolloConfig
import ApolloShellCore
import Carbon.HIToolbox

enum KeyboardLayout {
    @MainActor
    static func keyName(_ keyCode: UInt32) -> String? {
        guard HotKeyKey.isCharacterKey(keyCode),
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let text = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout -> String in
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
            )
            return status == noErr ? String(utf16CodeUnits: chars, count: length) : ""
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !trimmed.isEmpty else { return nil }
        let upper = trimmed.uppercased()
        return upper.count == trimmed.count ? upper : trimmed
    }

    @MainActor
    static func label(_ chord: KeyChord, keyName: @MainActor (UInt32) -> String?) -> String {
        guard HotKeyKey.isCharacterKey(chord.keyCode), let name = keyName(chord.keyCode) else { return chord.display }
        return chord.modifiers.symbols + name
    }
}
