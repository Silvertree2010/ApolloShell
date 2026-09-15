import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Bluetooth-Zustand aus system_profiler")
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

    @Test("aus")
    func off() {
        #expect(BluetoothStatus.powerOn(fromSystemProfilerJSON: json("attrib_off")) == false)
    }

    @Test("unbekannter Wert oder kaputte Ausgabe: nil statt Raten")
    func unknown() {
        #expect(BluetoothStatus.powerOn(fromSystemProfilerJSON: json("attrib_weird")) == nil)
        #expect(BluetoothStatus.powerOn(fromSystemProfilerJSON: Data("kein json".utf8)) == nil)
        #expect(BluetoothStatus.powerOn(fromSystemProfilerJSON: Data("{}".utf8)) == nil)
    }
}
