import Foundation

/// Symbol und Prozentzahl fuer die Lautstaerke-Anzeige (OSD).
public enum VolumeGlyphs {
    /// Stumm oder 0 -> durchgestrichen, sonst ein bis drei Wellen.
    public static func symbol(volume: Float, muted: Bool) -> String {
        if muted || volume <= 0.001 { return "speaker.slash.fill" }
        switch volume {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    /// Ganze Prozent, auf 0...100 begrenzt.
    public static func percent(_ volume: Float) -> Int {
        Int((min(max(volume, 0), 1) * 100).rounded())
    }
}
