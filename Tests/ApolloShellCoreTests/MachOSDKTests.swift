import Foundation
import Testing
@testable import ApolloShellCore

@Suite("The SDK an app was built with, read from its Mach-O header")
struct MachOSDKTests {
    /// A thin 64-bit arm64 binary with one load command.
    private func thin(_ command: [UInt32]) -> Data {
        var words: [UInt32] = [0xFEED_FACF, 0x0100_000C, 0, 2, 1, UInt32(command.count * 4), 0, 0]
        words += command
        return words.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func buildVersion(sdk: UInt32) -> [UInt32] {
        // cmd, cmdsize, platform (macOS), minos, sdk, ntools
        [0x32, 24, 1, 0x000B_0000, sdk, 0]
    }

    @Test func readsLCBuildVersion() {
        #expect(MachOSDK.major(of: thin(buildVersion(sdk: 0x000F_0200))) == 15)
        #expect(MachOSDK.major(of: thin(buildVersion(sdk: 0x001A_0000))) == 26)
    }

    @Test func readsTheOldVersionMinCommand() {
        // LC_VERSION_MIN_MACOSX: cmd, cmdsize, version, sdk
        #expect(MachOSDK.major(of: thin([0x24, 16, 0x000A_0D00, 0x000A_0E00])) == 10)
    }

    @Test func picksTheArm64SliceOfAUniversalBinary() {
        let intel = thin(buildVersion(sdk: 0x000E_0000))
        let arm = thin(buildVersion(sdk: 0x001A_0000))
        // Fat header, big-endian: magic, count, then per slice
        // cputype, cpusubtype, offset, size, align.
        let header: [UInt32] = [0xCAFE_BABE, 2,
                                0x0100_0007, 3, 4096, UInt32(intel.count), 12,
                                0x0100_000C, 0, 8192, UInt32(arm.count), 12]
        var data = header.map(\.bigEndian).withUnsafeBufferPointer { Data(buffer: $0) }
        data.append(Data(count: 4096 - data.count))
        data.append(intel)
        data.append(Data(count: 8192 - data.count))
        data.append(arm)
        #expect(MachOSDK.major(of: data) == 26)
    }

    @Test func garbageGivesNil() {
        #expect(MachOSDK.major(of: Data([1, 2, 3])) == nil)
        #expect(MachOSDK.major(of: thin([0x19, 8])) == nil)
    }

    @Test func readsARealApp() throws {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
        try #require(FileManager.default.fileExists(atPath: terminal.path))
        #expect((MachOSDK.major(ofExecutableAt: terminal) ?? 0) >= 26)
    }
}
