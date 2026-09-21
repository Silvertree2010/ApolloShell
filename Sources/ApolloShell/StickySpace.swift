import AppKit
import os

/// Ein eigener, immer sichtbarer Space fuer die Leisten, damit sie beim
/// Wechsel zwischen Schreibtischen stehen bleiben.
///
/// `.canJoinAllSpaces` + `.stationary` reicht dafuer nicht: gemessen 21.09.
/// (Video in der VM, 20 Bilder/s) verschwindet die Leiste beim Wisch fuer
/// ein paar Bilder und taucht erst nach der Animation wieder auf. So macht es
/// SketchyBar (`window.c`, Einstellung `sticky`): ein Space ueber
/// `SLSSpaceCreate`, auf Ebene 0, eingeblendet, und die Fenster dorthin
/// verschoben. Dieser Space nimmt am Wisch nicht teil.
///
/// Private Schnittstelle aus SkyLight, ueber `dlsym`: fehlt ein Symbol (ein
/// kuenftiges macOS), passiert nichts, und die Leiste verhaelt sich wie
/// vorher.
@MainActor
enum StickySpace {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    private static let log = Logger(category: "sticky")

    private static let api: (connection: Int32, add: AddWindows, space: UInt64)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let main = dlsym(handle, "SLSMainConnectionID"),
              let create = dlsym(handle, "SLSSpaceCreate"),
              let level = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(handle, "SLSShowSpaces"),
              let add = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else {
            log.notice("SkyLight-Spaces fehlen, Leisten wischen mit")
            return nil
        }
        let connection = unsafeBitCast(main, to: MainConnection.self)()
        let space = unsafeBitCast(create, to: SpaceCreate.self)(connection, 1, nil)
        guard space != 0 else {
            log.notice("SLSSpaceCreate lieferte keinen Space")
            return nil
        }
        _ = unsafeBitCast(level, to: SetAbsoluteLevel.self)(connection, space, 0)
        _ = unsafeBitCast(show, to: ShowSpaces.self)(connection, [NSNumber(value: space)] as CFArray)
        log.notice("eigener Space \(space, privacy: .public) fuer die Leisten")
        return (connection, unsafeBitCast(add, to: AddWindows.self), space)
    }()

    /// Das Fenster in den eigenen Space. Erst aufrufen, wenn es eine
    /// Fensternummer hat (nach dem ersten `orderFront`).
    static func pin(_ window: NSWindow) {
        guard let api, window.windowNumber > 0 else { return }
        let windows = [NSNumber(value: window.windowNumber)] as CFArray
        // 0x7 wie bei SketchyBar: aus allen bisherigen Spaces heraus.
        _ = api.add(api.connection, api.space, windows, 0x7)
    }
}
