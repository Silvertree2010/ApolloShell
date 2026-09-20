import Foundation
import Testing
@testable import ApolloShellCore

@Suite("The Bluetooth state out of system_profiler")
struct BluetoothStatusTests {
    private func json(_ state: String) -> Data {
        Data("""
        {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"\(state)","controller_transport":"PCIe"}}]}
        """.utf8)
    }

    @Test("an")
    func on() {
        #expect(BluetoothStatus.powerOn(fromSystemProfilerJSON: json("attrib_on")) == true)
    }

    @Test("off")
    func off() {
        #expect(BluetoothStatus.powerOn(fromSystemProfilerJSON: json("attrib_off")) == false)
    }

    @Test("an unknown value or broken output: nil instead of guessing")
    func unknown() {
        #expect(BluetoothStatus.powerOn(fromSystemProfilerJSON: json("attrib_weird")) == nil)
        #expect(BluetoothStatus.powerOn(fromSystemProfilerJSON: Data("no json".utf8)) == nil)
        #expect(BluetoothStatus.powerOn(fromSystemProfilerJSON: Data("{}".utf8)) == nil)
    }
}
