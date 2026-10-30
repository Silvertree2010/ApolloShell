public enum SystemKey: Equatable, Sendable {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown

    public init?(data1: Int) {
        switch (data1 & 0xFFFF0000) >> 16 {
        case 0: self = .volumeUp
        case 1: self = .volumeDown
        case 7: self = .mute
        case 2: self = .brightnessUp
        case 3: self = .brightnessDown
        default: return nil
        }
    }

    public static func isDown(data1: Int) -> Bool {
        ((data1 & 0xFF00) >> 8) == 0xA
    }

    public static func step(fine: Bool) -> Float {
        fine ? 1 / 64 : 1 / 16
    }

    public static func stepped(_ v: Float, by d: Float) -> Float {
        let n = (v / abs(d)).rounded() + (d > 0 ? 1 : -1)
        return min(max(n * abs(d), 0), 1)
    }
}
