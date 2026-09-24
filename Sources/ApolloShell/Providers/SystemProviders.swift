import Foundation
import ApolloConfig
import ApolloProviders
import ApolloRuntime

@MainActor
struct SystemProviders {
    let providers: [any ProviderInstance]
    let power: PowerProvider
    let system: SystemMacSource
    let wm: WMProvider

    init(directory: URL, socketPath: String?, polls: [ScriptSourceSpec], listens: [ScriptSourceSpec], clock: any RuntimeClock) {
        let apps = AppsProvider(source: SystemAppsSource(directory: directory), clock: clock)
        let window = WindowProvider(source: SystemWindowSource(), clock: clock)
        let system = SystemMacSource(directory: directory)
        let power = PowerProvider(source: SystemPowerSource(directory: directory), clock: clock)
        let runner = SystemScriptRunner(socketPath: socketPath)
        let wm = WMProvider(engine: SystemWMEngine(layoutFile: directory.appendingPathComponent("wm-layout.json")), clock: clock)
        self.power = power
        self.system = system
        self.wm = wm
        providers = [
            ClockProvider(source: SystemClockSource(), clock: clock),
            BatteryProvider(source: SystemBatterySource(), clock: clock),
            NetworkProvider(source: SystemWifiSource(), clock: clock),
            BluetoothProvider(source: SystemBluetoothSource(), clock: clock),
            AudioProvider(source: SystemAudioSource(), clock: clock),
            MediaProvider(source: SystemMediaSource(), clock: clock),
            PerfProvider(source: SystemPerfSource(), clock: clock),
            SpacesProvider(source: SystemSpacesSource(), clock: clock),
            apps,
            WeatherReportProvider(source: SystemWeatherSource(), clock: clock),
            KeyboardProvider(source: SystemKeyboardSource(), clock: clock),
            window,
            ScreensProvider(source: SystemScreensSource(), clock: clock),
            SystemProvider(source: system, clock: clock),
            SessionProvider(source: SystemSessionSource(), clock: clock),
            power,
            PermissionsProvider(source: SystemPermissionsSource(), clock: clock),
            ShortcutsProvider(source: SystemShortcutsSource(), clock: clock),
            ScriptSourcesProvider(kind: .poll, sources: polls, runner: runner, clock: clock),
            ScriptSourcesProvider(kind: .listen, sources: listens, runner: runner, clock: clock),
            wm,
        ]
    }

    var ids: [String] { providers.map(\.schema.id) }

    func terminate() {
        wm.shutdown()
        power.shutdown()
        system.terminate()
    }
}
