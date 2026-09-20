import Foundation
import Testing
@testable import ApolloShellCore

/// Shape like `system_profiler SPBluetoothDataType -json` on macOS 26
/// (measured 14.09.), values made up - no real addresses or
/// serial numbers. The disconnected "Headphone Max" carries, just like in reality, an
/// old battery value that must not be shown.
private let fixture = Data("""
{
  "SPBluetoothDataType" : [
    {
      "controller_properties" : {
        "controller_address" : "00:00:00:00:00:00",
        "controller_state" : "attrib_on",
        "controller_transport" : "PCIe"
      },
      "device_connected" : [
        { "Test AirPods Pro" : {
            "device_address" : "00:00:00:00:00:01",
            "device_batteryLevelCase" : "60%",
            "device_batteryLevelLeft" : "85%",
            "device_batteryLevelRight" : "90%",
            "device_minorType" : "Headphones"
        } },
        { "Test Keyboard" : {
            "device_address" : "00:00:00:00:00:02",
            "device_batteryLevelMain" : "42%",
            "device_minorType" : "Keyboard"
        } },
        { "Test Mouse" : {
            "device_address" : "00:00:00:00:00:03",
            "device_minorType" : "Mouse"
        } }
      ],
      "device_not_connected" : [
        { "Test AirPods Max" : {
            "device_address" : "00:00:00:00:00:04",
            "device_batteryLevelMain" : "100%",
            "device_minorType" : "Headphones"
        } },
        { "Test iPhone" : {
            "device_address" : "00:00:00:00:00:05"
        } }
      ]
    }
  ]
}
""".utf8)

@Suite("Detail window: Bluetooth devices from system_profiler")
struct StatusPopoutBluetoothTests {
    private var snapshot: StatusPopoutBluetoothSnapshot? {
        StatusPopoutBluetoothParser.snapshot(fromSystemProfilerJSON: fixture)
    }

    @Test("State and count: 3 connected, 5 paired", arguments: [(true, 3, 5)])
    func counts(powerOn: Bool, connected: Int, paired: Int) throws {
        let snapshot = try #require(snapshot)
        #expect(snapshot.powerOn == powerOn)
        #expect(snapshot.connected.count == connected)
        #expect(snapshot.pairedCount == paired)
    }

    @Test("connected first, then disconnected, each in original order", arguments: [
        ["Test AirPods Pro", "Test Keyboard", "Test Mouse", "Test AirPods Max", "Test iPhone"],
    ])
    func order(names: [String]) throws {
        #expect(try #require(snapshot).devices.map(\.name) == names)
    }

    @Test("Battery values per device, disconnected ones without a stale value", arguments: [
        ("Test AirPods Pro", ["L 85", "R 90", "Case 60"]),
        ("Test Keyboard", ["42"]),
        ("Test Mouse", []),
        ("Test AirPods Max", []),
    ])
    func batteries(name: String, expected: [String]) throws {
        let device = try #require(snapshot?.devices.first { $0.name == name })
        let texts = device.batteries.map { [$0.label, String($0.percent)].compactMap { $0 }.joined(separator: " ") }
        #expect(texts == expected)
    }

    @Test("Symbol by name and device type", arguments: [
        ("Test AirPods Pro", "airpodspro"), ("Test AirPods Max", "airpodsmax"),
        ("Test Keyboard", "keyboard"), ("Test Mouse", "computermouse"), ("Test iPhone", "iphone"),
    ])
    func symbol(name: String, symbol: String) throws {
        #expect(try #require(snapshot?.devices.first { $0.name == name }).symbol == symbol)
    }

    @Test("Percent as text", arguments: [
        ("85%", Int?.some(85)), (" 7 %", Int?.some(7)), ("full", Int?.none), ("140%", Int?.none),
    ])
    func percentText(value: String, expected: Int?) {
        #expect(StatusPopoutBluetoothParser.percent(value) == expected)
    }

    @Test("Percent as number", arguments: [(50, Int?.some(50)), (-3, Int?.none)])
    func percentNumber(value: Int, expected: Int?) {
        #expect(StatusPopoutBluetoothParser.percent(value) == expected)
    }

    @Test("Missing value: nil")
    func percentMissing() {
        #expect(StatusPopoutBluetoothParser.percent(nil) == nil)
    }

    @Test("broken or empty output: nil or no devices", arguments: ["not json", "{}"])
    func broken(text: String) {
        #expect(StatusPopoutBluetoothParser.snapshot(fromSystemProfilerJSON: Data(text.utf8)) == nil)
    }
}
