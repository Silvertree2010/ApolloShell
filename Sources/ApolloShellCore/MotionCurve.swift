import Foundation

/// Kontrollpunkte einer CSS-Bezierkurve, `cubic-bezier(x1, y1, x2, y2)`.
public struct MotionCurve: Equatable, Sendable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    /// Caelestias expressiveDefaultSpatial (plugin/src/Caelestia/Config/
    /// tokens.hpp): schiesst leicht ueber (y1 = 1,21) und rastet ein. Die
    /// Standardbewegung der Shell fuer Groesse und Lage - Panels, Popout,
    /// Kurzmeldungen, Anzeiger.
    public static let spatial = MotionCurve(0.38, 1.21, 0.22, 1)
    /// Dauer, die Caelestia dazu nimmt.
    public static let spatialDuration: Double = 0.5
}
