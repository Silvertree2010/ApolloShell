import AppKit
import ApolloShellCore
import Carbon
import SwiftUI

@MainActor
enum OSDBrightness {
    private typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (UInt32, Float) -> Int32
    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getF: Get? = lib.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    private static let setF: Set? = lib.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }

    static func get() -> Float? {
        guard let getF else { return nil }
        var v: Float = 0
        return getF(CGMainDisplayID(), &v) == 0 ? v : nil
    }

    static func set(_ v: Float) {
        _ = setF?(CGMainDisplayID(), min(max(v, 0), 1))
    }
}

@MainActor
@Observable
final class OSDInfoModel {
    var symbol = "keyboard"
    var text = ""
}

struct OSDInfoView: View {
    let model: OSDInfoModel
    @Environment(\.shellStyle) private var style

    static let size = NSSize(width: 280, height: 52)

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(style.paint(.secondaryText, or: .secondary))
            Text(model.text)
                .font(style.font(size: 14, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(style.paint(.text, or: .primary))
        }
        .padding(.horizontal, 18)
        .frame(width: Self.size.width, height: Self.size.height)
        .contentTransition(.opacity)
    }
}

@MainActor
final class OSDExtras {
    private let osd: OSD
    private let info = OSDInfoModel()
    private let drawer: EdgeDrawer<OSDInfoView>
    private var keys: Any?
    private var flags: Any?
    private var hide: Timer?
    private var caps = NSEvent.modifierFlags.contains(.capsLock)
    private var layoutObserver: (any NSObjectProtocol)?
    private var lastLayout = OSDExtras.layoutName()

    init(osd: OSD) {
        self.osd = osd
        drawer = EdgeDrawer(edge: .bottom, size: OSDInfoView.size, cornerRadius: 22, takesKeyboard: false,
                            motion: .grow, rootView: OSDInfoView(model: info))
        drawer.closesOnResignKey = false
        keys = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] e in
            guard e.subtype.rawValue == 8 else { return }
            let code = (e.data1 & 0xFFFF0000) >> 16
            let down = ((e.data1 & 0xFF00) >> 8) == 0xA
            guard down, code == 2 || code == 3 else { return }
            MainActor.assumeIsolated { self?.brightnessKey() }
        }
        flags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            let on = e.modifierFlags.contains(.capsLock)
            MainActor.assumeIsolated { self?.capsChanged(on) }
        }
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutChanged() }
        }
    }

    private func brightnessKey() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            if let v = OSDBrightness.get() { self?.osd.showBrightness(v) }
        }
    }

    private func capsChanged(_ on: Bool) {
        guard on != caps else { return }
        caps = on
        show(on ? "capslock.fill" : "capslock", on ? String(localized: "Caps Lock On") : String(localized: "Caps Lock Off"))
    }

    private func layoutChanged() {
        let n = Self.layoutName()
        guard n != lastLayout else { return }
        lastLayout = n
        show("keyboard", n)
    }

    private func show(_ sym: String, _ text: String) {
        info.symbol = sym
        info.text = text
        drawer.open()
        hide?.invalidate()
        hide = .once(after: 1.5, owner: self) { $0.drawer.close() }
    }

    static func layoutName() -> String {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let p = TISGetInputSourceProperty(src, kTISPropertyLocalizedName) else { return "" }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
}
