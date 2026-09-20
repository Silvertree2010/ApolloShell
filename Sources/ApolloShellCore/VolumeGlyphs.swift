import Foundation

/// Symbol and percentage for the volume display (OSD).
public enum VolumeGlyphs {
    /// Muted or 0 -> struck through, otherwise one to three waves.
    public static func symbol(volume: Float, muted: Bool) -> String {
        if muted || volume <= 0.001 { return "speaker.slash.fill" }
        switch volume {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    /// Whole percent, clamped to 0...100.
    public static func percent(_ volume: Float) -> Int {
        Int((min(max(volume, 0), 1) * 100).rounded())
    }
}
