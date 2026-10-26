import CoreGraphics

/// Kante, an der die Leiste steht (Nexus > Leiste > Position).
///
/// Rechts wird alles von links gespiegelt gerechnet: dieselbe Rechnung, nur
/// mit an der Mitte des Bildschirms gespiegelten Rechtecken (`mirrored`).
public enum BarSide: String, Codable, CaseIterable, Sendable {
    case left, right

    /// `rect` an der senkrechten Mittellinie von `bounds` gespiegelt. Ihre
    /// eigene Umkehrung.
    public static func mirrored(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + bounds.maxX - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }
}
