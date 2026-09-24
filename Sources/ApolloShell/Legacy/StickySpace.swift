import AppKit
import os

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

    static func pin(_ window: NSWindow) {
        guard let api, window.windowNumber > 0 else { return }
        let windows = [NSNumber(value: window.windowNumber)] as CFArray
        _ = api.add(api.connection, api.space, windows, 0x7)
    }
}
