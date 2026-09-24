enum SpecFixture {
    static let text = """
    fixture {
        clock now="2026-09-24T09:41:00+02:00"
        battery present=#true percent=0.76 charging=#false on-power=#false
        network {
            wifi on=#true connected=#true rssi=-52 bars=3
        }
        bluetooth on=#true status="ready" paired=2 connected=1
        audio volume=0.35 muted=#false {
            output id="builtin" name="MacBook Pro Speakers"
        }
        perf cpu=0.42 {
            live cpu=0.42 memory=0.61
        }
        weather status="ready" {
            place name="Chur" latitude=46.85 longitude=9.53
            current temperature=14 symbol="cloud.sun.fill" description="Partly Cloudy" is-day=#true
        }
        media available=#true playing=#true title="Starboy" artist="The Weeknd" album="Starboy" kind="music"
        spaces current=2 count=4 {
            list {
                - id=1 index=1 active=#false fullscreen=#false
                - id=2 index=2 active=#true fullscreen=#false
                - id=3 index=3 active=#false fullscreen=#false
                - id=4 index=4 active=#false fullscreen=#false
            }
        }
        apps {
            dock {
                - bundle-id="com.apple.finder" name="Finder" running=#true section="file-manager"
                - bundle-id="com.apple.Safari" name="Safari" running=#true dock-pinned=#true section="pinned"
                - bundle-id="com.apple.mail" name="Mail" running=#false dock-pinned=#true section="pinned" badge="3"
            }
        }
    }
    """
}
