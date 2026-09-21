import AppKit
import os

/// A space of its own, always shown, for the bars, so they stay put while
/// switching desktops.
///
/// `.canJoinAllSpaces` + `.stationary` is not enough for that: measured
/// 21.09. (a video in the VM, 20 frames a second), the bar vanishes for a few
/// frames during the swipe and only comes back after the animation. This is
/// how SketchyBar does it (`window.c`, setting `sticky`): a space through
/// `SLSSpaceCreate`, on level 0, shown, and the windows moved into it. That
/// space takes no part in the swipe.
///
/// Private interface out of SkyLight, through `dlsym`: when a symbol is
/// missing (a future macOS), nothing happens and the bar behaves as before.
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
            log.notice("SkyLight spaces missing, bars swipe along")
            return nil
        }
        let connection = unsafeBitCast(main, to: MainConnection.self)()
        let space = unsafeBitCast(create, to: SpaceCreate.self)(connection, 1, nil)
        guard space != 0 else {
            log.notice("SLSSpaceCreate returned no space")
            return nil
        }
        _ = unsafeBitCast(level, to: SetAbsoluteLevel.self)(connection, space, 0)
        _ = unsafeBitCast(show, to: ShowSpaces.self)(connection, [NSNumber(value: space)] as CFArray)
        log.notice("own space \(space, privacy: .public) for the bars")
        return (connection, unsafeBitCast(add, to: AddWindows.self), space)
    }()

    /// Moves the window into the own space. Call only once it has a window
    /// number (after the first `orderFront`).
    static func pin(_ window: NSWindow) {
        guard let api, window.windowNumber > 0 else { return }
        let windows = [NSNumber(value: window.windowNumber)] as CFArray
        // 0x7 as with SketchyBar: out of every space it was in so far.
        _ = api.add(api.connection, api.space, windows, 0x7)
    }
}
