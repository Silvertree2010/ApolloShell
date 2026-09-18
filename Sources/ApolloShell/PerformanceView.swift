import ApolloShellCore
import SwiftUI

/// Die Widgets der Seite "Leistung" (CPU, GPU, Speicher, Netzwerk,
/// Arbeitsspeicher, Akku) zeichnet `WidgetView` einzeln, an ihren Rahmen aus
/// `PageTemplate.performance` (`DashboardPagesDefaults.swift`). Hier bleibt
/// nur die gemeinsame Kurve fuer ihre Animationen.
enum PerformanceAnimation {
    /// Caelestias Standardkurve: 500 ms, leicht ueberschiessend.
    static let value = Animation.shellSpatial
}

// MARK: - CPU/GPU

/// Caelestia HeroCard: Ring mit Symbol, Titel in Akzentfarbe, Untertitel,
/// rechts unten die Auslastung gross in einer Form, die mit der Last
/// zackiger wird (Caelestia: Cookie < 40 %, Sunny < 80 %, SoftBurst).
struct HeroCard: View {
    let symbol: String
    /// Kennung fuer den Symbol-Austausch im Theme.
    var iconID: String = ""
    let title: String
    let subtitle: String
    let value: Double?
    let history: SampleHistory
    @Environment(\.shellStyle) private var style

    var body: some View {
        Card(radius: 24) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    UsageRing(value: value ?? 0, symbol: symbol, iconID: iconID)
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(style.font(size: 19, weight: .semibold))
                            .foregroundStyle(style.accent)
                        Text(subtitle)
                            .font(style.font(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 8)
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Letzte 30 s")
                            .font(style.font(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                        SparklineArea(values: history.values, capacity: history.capacity, scale: 1,
                                      color: style.accent, fillOpacity: 0.18)
                            .frame(height: 40)
                            .background(alignment: .bottom) {
                                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                            }
                    }
                    UsageBadge(value: value)
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(PerformanceText.percent(value))")
    }
}

private struct UsageRing: View {
    let value: Double
    let symbol: String
    /// Kennung fuer den Symbol-Austausch im Theme.
    var iconID: String = ""
    @Environment(\.shellStyle) private var style

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(style.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(PerformanceAnimation.value, value: value)
            ThemedIcon(iconID.isEmpty ? symbol : iconID, fallback: symbol)
                .font(style.font(size: 17, weight: .medium))
                .frame(width: 19, height: 19)
        }
        .padding(2)
    }
}

private struct UsageBadge: View {
    let value: Double?
    @Environment(\.shellStyle) private var style

    var body: some View {
        let usage = value ?? 0
        ZStack {
            ScallopShape(lobes: usage >= 0.8 ? 12 : usage >= 0.4 ? 8 : 4,
                         depth: usage >= 0.8 ? 0.11 : usage >= 0.4 ? 0.07 : 0.12)
                .fill(style.accent)
            Text(PerformanceText.percent(value))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(style.onAccent)
                .contentTransition(.numericText(value: usage))
                .animation(PerformanceAnimation.value, value: usage)
        }
        .frame(width: 92, height: 92)
    }
}

/// Kreis mit gewellter Kante - Ersatz fuer Caelestias Material-Formen
/// (Cookie/Sunny/SoftBurst), die es in SwiftUI nicht gibt.
private struct ScallopShape: Shape {
    let lobes: Int
    let depth: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        let steps = 180
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            // Radius schwingt zwischen aussen und (1 - depth) * aussen.
            let radius = outer * (1 - depth * (1 - cos(Double(lobes) * angle)) / 2)
            let point = CGPoint(x: center.x + radius * cos(angle - .pi / 2),
                                y: center.y + radius * sin(angle - .pi / 2))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Speicher

/// Caelestia-Tacho: 270 Grad, Luecke unten (Start -225 Grad), dort steht
/// die Beschriftung.
private struct ArcGauge<Label: View>: View {
    let value: Double
    let caption: LocalizedStringKey
    @ViewBuilder let label: () -> Label
    @Environment(\.shellStyle) private var style

    private let lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            arc(to: 1).stroke(Color.primary.opacity(0.10), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            arc(to: value)
                .stroke(style.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .animation(PerformanceAnimation.value, value: value)
            label()
            Text(caption)
                .font(style.font(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// SwiftUIs Kreis beginnt rechts (3 Uhr) im Uhrzeigersinn; um 135 Grad
    /// gedreht beginnt er links unten - das ist Caelestias -225 Grad.
    private func arc(to fraction: Double) -> some Shape {
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: 0.75 * min(max(fraction, 0), 1))
            .rotation(.degrees(135))
    }
}

private struct PercentLabel: View {
    let value: Double?

    var body: some View {
        Text(PerformanceText.percent(value))
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: value ?? 0))
            .animation(PerformanceAnimation.value, value: value)
    }
}

struct StorageCard: View {
    let usage: ByteUsage?
    @Environment(\.shellStyle) private var style

    var body: some View {
        Card(radius: 41) {
            VStack(spacing: 6) {
                ArcGauge(value: usage?.fraction ?? 0, caption: "Belegt") {
                    VStack(spacing: 0) {
                        ThemedIcon("panel-disk", fallback: "internaldrive.fill")
                            .font(style.font(size: 15, weight: .medium))
                            .frame(width: 17, height: 17)
                            .foregroundStyle(style.accent)
                        PercentLabel(value: usage?.fraction)
                    }
                    .offset(y: -2)
                }
                .frame(width: 122, height: 122)
                Text(usage.map { ByteFormat.usage(used: $0.used, total: $0.total) } ?? "–")
                    .font(style.font(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
        }
        .help("Startvolume")
    }
}

struct MemoryCard: View {
    let usage: ByteUsage?
    @Environment(\.shellStyle) private var style

    var body: some View {
        Card(radius: 10) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ThemedIcon("panel-memory", fallback: "memorychip.fill")
                        .font(style.font(size: 13, weight: .semibold))
                        .frame(width: 15, height: 15)
                        .foregroundStyle(style.accent)
                    Text("Arbeitsspeicher")
                        .font(style.font(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                ArcGauge(value: usage?.fraction ?? 0, caption: "Belegt") {
                    PercentLabel(value: usage?.fraction)
                }
                .frame(width: 110, height: 110)
                // Binaer wie die Aktivitaetsanzeige: 24 GB RAM bleiben 24 GB.
                Text(usage.map { ByteFormat.usage(used: $0.used, total: $0.total, binary: true) } ?? "–")
                    .font(style.font(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Netzwerk

struct NetworkCard: View {
    let model: PerformanceModel
    @Environment(\.shellStyle) private var style

    /// Upload in einer zweiten Farbe, damit sich die Linien trennen lassen
    /// (Caelestia: sekundaere und tertiaere Palettenfarbe).
    private let uploadColor = Color.orange

    var body: some View {
        // Beide Linien auf derselben Skala, sonst waeren sie nicht vergleichbar.
        let scale = Sparkline.scale(
            peak: max(model.downloadHistory.peak, model.uploadHistory.peak),
            floor: 10_000
        )
        Card(radius: 24) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(style.font(size: 13, weight: .semibold))
                        .foregroundStyle(style.accent)
                    Text("Netzwerk").font(style.font(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("max \(ByteFormat.rate(scale))")
                        .font(style.font(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                ZStack {
                    SparklineArea(values: model.uploadHistory.values, capacity: model.uploadHistory.capacity,
                                  scale: scale, color: uploadColor, fillOpacity: 0.15)
                    SparklineArea(values: model.downloadHistory.values, capacity: model.downloadHistory.capacity,
                                  scale: scale, color: style.accent, fillOpacity: 0.2)
                }
                .background(alignment: .bottom) {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                }
                .frame(maxHeight: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 8)
                VStack(spacing: 4) {
                    RateRow(symbol: "arrow.down", color: style.accent, title: "Download",
                            value: model.network.map { ByteFormat.rate($0.download) } ?? "–")
                    RateRow(symbol: "arrow.up", color: uploadColor, title: "Upload",
                            value: model.network.map { ByteFormat.rate($0.upload) } ?? "–")
                    RateRow(symbol: "clock.arrow.circlepath", color: .secondary, title: "Gesamt",
                            value: "↓ \(ByteFormat.bytes(Double(model.networkTotal.received)))   ↑ \(ByteFormat.bytes(Double(model.networkTotal.sent)))")
                        .help("Seit dem ersten Öffnen dieses Reiters")
                }
            }
            .padding(14)
        }
    }
}

private struct RateRow: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let value: String
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(style.font(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(title).font(style.font(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(style.font(size: 12, weight: .medium)).monospacedDigit().lineLimit(1)
        }
    }
}

// MARK: - Verlaufslinie

/// Linie mit leicht gefuellter Flaeche darunter (Caelestia: 15-20 % Deckkraft).
private struct SparklineArea: View {
    let values: [Double]
    let capacity: Int
    let scale: Double
    let color: Color
    let fillOpacity: Double

    var body: some View {
        ZStack {
            SparklineShape(values: values, capacity: capacity, scale: scale, closed: true)
                .fill(color.opacity(fillOpacity))
            SparklineShape(values: values, capacity: capacity, scale: scale, closed: false)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        // Der Strich soll oben am Maximum nicht halb abgeschnitten wirken.
        .padding(.top, 1)
        .animation(PerformanceAnimation.value, value: scale)
    }
}

/// Die Skala ist animierbar: springt das Maximum, gleitet die y-Achse mit.
private struct SparklineShape: Shape {
    let values: [Double]
    let capacity: Int
    var scale: Double
    let closed: Bool

    var animatableData: Double {
        get { scale }
        set { scale = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let points = Sparkline.points(values, capacity: capacity, scale: scale).map {
            CGPoint(x: rect.minX + $0.x * rect.width, y: rect.maxY - $0.y * rect.height)
        }
        guard let first = points.first, let last = points.last, points.count > 1 else { return Path() }
        var path = Path()
        path.move(to: first)
        // Weich ueber die Mittelpunkte, damit die Zacken nicht hart knicken.
        for index in 1..<points.count {
            let previous = points[index - 1]
            let mid = CGPoint(x: (previous.x + points[index].x) / 2, y: (previous.y + points[index].y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        path.addLine(to: last)
        if closed {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Akku

/// Caelestia BatteryTank: fuellt sich von unten wie Fluessigkeit. Der
/// Inhalt liegt zweimal da - einmal normal, einmal in umgekehrten Farben
/// auf die Fuellung maskiert -, so bleibt jede Schrift lesbar, egal wo die
/// Kante gerade durch sie laeuft.
struct BatteryTank: View {
    let state: BatteryState
    let minutes: Int?
    @Environment(\.shellStyle) private var style

    var body: some View {
        GeometryReader { geometry in
            let fill = geometry.size.height * BatteryTankText.fill(state)
            ZStack(alignment: .bottom) {
                Color.primary.opacity(0.06)
                TankContents(state: state, minutes: minutes, inverted: false)
                Rectangle().fill(style.accent).frame(height: fill)
                TankContents(state: state, minutes: minutes, inverted: true)
                    .mask(alignment: .bottom) { Rectangle().frame(height: fill) }
            }
            .animation(PerformanceAnimation.value, value: state.level)
        }
        .clipShape(.rect(cornerRadius: style.cardRadius(14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StatusGlyphs.batteryText(state))
    }
}

private struct TankContents: View {
    let state: BatteryState
    let minutes: Int?
    let inverted: Bool
    @Environment(\.shellStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: StatusGlyphs.batterySymbol(state) ?? "battery.100percent")
                    .font(style.font(size: 14, weight: .medium))
                Text("Akku").font(style.font(size: 15, weight: .semibold))
            }
            .foregroundStyle(inverted ? style.onAccent : style.accent)
            Spacer(minLength: 0)
            if state.charging {
                Image(systemName: "bolt.fill")
                    .font(style.font(size: 20, weight: .semibold))
                    .transition(.scale.combined(with: .opacity))
            }
            Text(BatteryTankText.percent(state))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(state.level)))
            Text(BatteryTankText.status(state, minutes: minutes))
                .font(style.font(size: 12))
                .foregroundStyle(inverted ? style.onAccent.opacity(0.85) : Color.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(inverted ? style.onAccent : Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }
}
