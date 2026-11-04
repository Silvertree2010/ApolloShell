import ApolloShellCore
import SwiftUI

/// The widgets of the "Performance" page (CPU, GPU, storage, network, memory,
/// battery) are drawn one by one by `WidgetView`, at their frames out of
/// `PageTemplate.performance` (`DashboardPagesDefaults.swift`). Only the shared
/// curve for their animations stays here.
enum PerformanceAnimation {
    /// Caelestia's standard curve: 500 ms, slightly overshooting.
    static let value = Animation.shellSpatial
}

// MARK: - CPU/GPU

/// Caelestia HeroCard: a ring with a symbol, the title in the accent color, a
/// subtitle, at the bottom right the load in big, in a shape that gets more
/// jagged with the load (Caelestia: Cookie < 40 %, Sunny < 80 %, SoftBurst).
struct HeroCard: View {
    let symbol: String
    /// The id for the symbol swap in the theme.
    var iconID: String = ""
    let title: String
    let subtitle: String
    let value: Double?
    let history: SampleHistory
    /// The height of the widget: below 150 the compact row, above the page
    /// size (191) the history grows into the extra room.
    var height: CGFloat = 191
    @Environment(\.shellStyle) private var style

    var body: some View {
        if height < 150 {
            compact
        } else if height > 200 {
            tall
        } else {
            full
        }
    }

    /// 250 and 392 tall: the badge moves up next to the title, and the
    /// history gets the whole width below - squeezed next to the badge it
    /// turned into spikes.
    private var tall: some View {
        Card(radius: 24) {
            VStack(alignment: .leading, spacing: 12) {
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
                    Spacer(minLength: 8)
                    UsageBadge(value: value, side: 76)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last 30s")
                        .font(style.font(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    SparklineArea(values: history.values, capacity: history.capacity, scale: 1,
                                  color: style.accent, fillOpacity: 0.18)
                        .frame(maxHeight: .infinity)
                        .background(alignment: .bottom) {
                            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                        }
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(PerformanceText.percent(value))")
    }

    /// 130 tall: the ring and the title on top, the history and the load in
    /// one row below - the scalloped badge would not fit.
    private var compact: some View {
        Card(radius: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    UsageRing(value: value ?? 0, symbol: symbol, iconID: iconID)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(style.font(size: 15, weight: .semibold))
                            .foregroundStyle(style.accent)
                        Text(subtitle)
                            .font(style.font(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(PerformanceText.percent(value))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .fixedSize()
                        .contentTransition(.numericText(value: value ?? 0))
                        .animation(PerformanceAnimation.value, value: value)
                }
                SparklineArea(values: history.values, capacity: history.capacity, scale: 1,
                              color: style.accent, fillOpacity: 0.18)
                    .frame(maxHeight: .infinity)
                    .background(alignment: .bottom) {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                    }
            }
            .padding(14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(PerformanceText.percent(value))")
    }

    private var full: some View {
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
                        Text("Last 30s")
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
    /// The id for the symbol swap in the theme.
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
    var side: CGFloat = 92
    @Environment(\.shellStyle) private var style

    var body: some View {
        let usage = value ?? 0
        ZStack {
            ScallopShape(lobes: usage >= 0.8 ? 12 : usage >= 0.4 ? 8 : 4,
                         depth: usage >= 0.8 ? 0.11 : usage >= 0.4 ? 0.07 : 0.12)
                .fill(style.accent)
            Text(PerformanceText.percent(value))
                .font(.system(size: side * 24 / 92, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(style.onAccent)
                .contentTransition(.numericText(value: usage))
                .animation(PerformanceAnimation.value, value: usage)
        }
        .frame(width: side, height: side)
    }
}

/// A circle with a wavy edge - a stand-in for Caelestia's Material shapes
/// (Cookie/Sunny/SoftBurst), which do not exist in SwiftUI.
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
            // The radius swings between the outside and (1 - depth) * outside.
            let radius = outer * (1 - depth * (1 - cos(Double(lobes) * angle)) / 2)
            let point = CGPoint(x: center.x + radius * cos(angle - .pi / 2),
                                y: center.y + radius * sin(angle - .pi / 2))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Storage

/// Caelestia's gauge: 270 degrees, the gap at the bottom (starting at -225
/// degrees), where the label stands.
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

    /// SwiftUI's circle begins on the right (3 o'clock) clockwise; turned by
    /// 135 degrees it begins at the bottom left - that is Caelestia's -225 degrees.
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
    var size = CGSize(width: 169.5, height: 189)
    @Environment(\.shellStyle) private var style

    var body: some View {
        if size.height < 150 {
            UsageRow(title: "Storage", iconID: "panel-disk", symbol: "internaldrive.fill", usage: usage, binary: false,
                     width: size.width)
                .help("Startup Volume")
        } else if size.height > 200 {
            UsageTall(title: "Storage", iconID: "panel-disk", symbol: "internaldrive.fill", usage: usage,
                      binary: false, size: size)
                .help("Startup Volume")
        } else {
            page
        }
    }

    private var page: some View {
        Card(radius: 41) {
            VStack(spacing: 6) {
                ArcGauge(value: usage?.fraction ?? 0, caption: "Used") {
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
        .help("Startup Volume")
    }
}

struct MemoryCard: View {
    let usage: ByteUsage?
    var size = CGSize(width: 169.5, height: 189)
    @Environment(\.shellStyle) private var style

    var body: some View {
        if size.height < 150 {
            UsageRow(title: "Memory", iconID: "panel-memory", symbol: "memorychip.fill", usage: usage, binary: true,
                     width: size.width)
        } else if size.height > 200 {
            UsageTall(title: "Memory", iconID: "panel-memory", symbol: "memorychip.fill", usage: usage,
                      binary: true, size: size)
        } else {
            page
        }
    }

    private var page: some View {
        Card(radius: 10) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ThemedIcon("panel-memory", fallback: "memorychip.fill")
                        .font(style.font(size: 13, weight: .semibold))
                        .frame(width: 15, height: 15)
                        .foregroundStyle(style.accent)
                    Text("Memory")
                        .font(style.font(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                ArcGauge(value: usage?.fraction ?? 0, caption: "Used") {
                    PercentLabel(value: usage?.fraction)
                }
                .frame(width: 110, height: 110)
                // Binary like Activity Monitor: 24 GB of RAM stay 24 GB.
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

// MARK: - Storage and memory in the other sizes

/// 130 tall: a small gauge on the left, the title and the numbers next to it.
private struct UsageRow: View {
    let title: LocalizedStringKey
    let iconID: String
    let symbol: String
    let usage: ByteUsage?
    let binary: Bool
    var width: CGFloat = 200
    @Environment(\.shellStyle) private var style

    var body: some View {
        let gauge = min(92, width * 0.4)
        Card(radius: 24) {
            HStack(spacing: 12) {
                ArcGauge(value: usage?.fraction ?? 0, caption: "") {
                    Text(PerformanceText.percent(usage?.fraction))
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: gauge, height: gauge)
                VStack(alignment: .leading, spacing: 4) {
                    UsageTitle(title: title, iconID: iconID, symbol: symbol)
                    Text(usage.map { ByteFormat.usage(used: $0.used, total: $0.total, binary: binary) } ?? "–")
                        .font(style.font(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
        }
    }
}

/// 250 and 392 tall: the gauge as large as the card allows, the title above it.
private struct UsageTall: View {
    let title: LocalizedStringKey
    let iconID: String
    let symbol: String
    let usage: ByteUsage?
    let binary: Bool
    let size: CGSize
    @Environment(\.shellStyle) private var style

    var body: some View {
        let gauge = min(size.width - 40, size.height - 96, 220)
        Card(radius: 28) {
            VStack(spacing: 8) {
                UsageTitle(title: title, iconID: iconID, symbol: symbol)
                ArcGauge(value: usage?.fraction ?? 0, caption: "Used") {
                    Text(PerformanceText.percent(usage?.fraction))
                        .font(.system(size: gauge * 0.26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: usage?.fraction ?? 0))
                        .animation(PerformanceAnimation.value, value: usage?.fraction)
                }
                .frame(width: gauge, height: gauge)
                Text(usage.map { ByteFormat.usage(used: $0.used, total: $0.total, binary: binary) } ?? "–")
                    .font(style.font(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct UsageTitle: View {
    let title: LocalizedStringKey
    let iconID: String
    let symbol: String
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 6) {
            ThemedIcon(iconID, fallback: symbol)
                .font(style.font(size: 13, weight: .semibold))
                .frame(width: 15, height: 15)
                .foregroundStyle(style.accent)
            Text(title)
                .font(style.font(size: 13, weight: .semibold))
                .fixedSize()
        }
    }
}

/// Display "bar": the load as a big number and a bar - reads at a glance in
/// every size, and next to other bars they line up.
struct UsageBarCard: View {
    let title: LocalizedStringKey
    let iconID: String
    let symbol: String
    let usage: ByteUsage?
    let binary: Bool
    let size: CGSize
    @Environment(\.shellStyle) private var style

    var body: some View {
        let big = size.height >= 200
        Card(radius: 24) {
            VStack(alignment: .leading, spacing: big ? 12 : 8) {
                UsageTitle(title: title, iconID: iconID, symbol: symbol)
                Spacer(minLength: 0)
                Text(PerformanceText.percent(usage?.fraction))
                    .font(.system(size: big ? 44 : 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: usage?.fraction ?? 0))
                    .animation(PerformanceAnimation.value, value: usage?.fraction)
                UsageBar(value: usage?.fraction ?? 0, height: big ? 12 : 8)
                Text(usage.map { ByteFormat.usage(used: $0.used, total: $0.total, binary: binary) } ?? "–")
                    .font(style.font(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(16)
        }
    }
}

struct UsageBar: View {
    let value: Double
    var height: CGFloat = 8
    @Environment(\.shellStyle) private var style

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(style.accent)
                    .frame(width: max(height, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(PerformanceAnimation.value, value: value)
    }
}

// MARK: - CPU and GPU, the other displays

/// Display "graph": the history fills the card, title and load sit on it.
struct HeroGraphCard: View {
    let symbol: String
    var iconID: String = ""
    let title: String
    let subtitle: String
    let value: Double?
    let history: SampleHistory
    @Environment(\.shellStyle) private var style

    var body: some View {
        Card(radius: 24) {
            ZStack(alignment: .topLeading) {
                SparklineArea(values: history.values, capacity: history.capacity, scale: 1,
                              color: style.accent, fillOpacity: 0.22)
                    .padding(.top, 44)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            ThemedIcon(iconID.isEmpty ? symbol : iconID, fallback: symbol)
                                .font(style.font(size: 13, weight: .semibold))
                                .frame(width: 15, height: 15)
                            Text(title).font(style.font(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(style.accent)
                        Text(subtitle)
                            .font(style.font(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(PerformanceText.percent(value))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: value ?? 0))
                        .animation(PerformanceAnimation.value, value: value)
                }
                .padding(14)
            }
            .clipShape(.rect(cornerRadius: style.cardRadius(24), style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(PerformanceText.percent(value))")
    }
}

/// Display "gauge": the load on the same 270-degree gauge as storage.
struct HeroGaugeCard: View {
    let symbol: String
    var iconID: String = ""
    let title: String
    let subtitle: String
    let value: Double?
    let size: CGSize
    @Environment(\.shellStyle) private var style

    var body: some View {
        let wide = size.width > size.height * 1.4
        let gauge = wide ? min(size.height - 28, 220) : min(size.width - 40, size.height - 84, 240)
        Card(radius: 24) {
            let label = VStack(alignment: wide ? .leading : .center, spacing: 1) {
                HStack(spacing: 6) {
                    ThemedIcon(iconID.isEmpty ? symbol : iconID, fallback: symbol)
                        .font(style.font(size: 13, weight: .semibold))
                        .frame(width: 15, height: 15)
                    Text(title).font(style.font(size: 15, weight: .semibold)).fixedSize()
                }
                .foregroundStyle(style.accent)
                Text(subtitle)
                    .font(style.font(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(wide ? 2 : 1)
            }
            let dial = ArcGauge(value: value ?? 0, caption: "") {
                Text(PerformanceText.percent(value))
                    .font(.system(size: gauge * 0.24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value ?? 0))
                    .animation(PerformanceAnimation.value, value: value)
            }
            .frame(width: gauge, height: gauge)
            if wide {
                HStack(spacing: 18) {
                    label
                    Spacer(minLength: 0)
                    dial
                }
                .padding(.horizontal, 18)
            } else {
                VStack(spacing: 10) {
                    label
                    dial
                }
                .padding(14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(PerformanceText.percent(value))")
    }
}

// MARK: - Network

struct NetworkCard: View {
    let model: PerformanceModel
    var height: CGFloat = 189
    @Environment(\.shellStyle) private var style

    /// The upload in a second color, so that the lines can be told apart
    /// (Caelestia: the secondary and tertiary palette color) - from the
    /// theme or the accent, `ShellStyle.contrastAccent`.
    private var uploadColor: Color { style.contrastAccent }

    var body: some View {
        // Both lines on the same scale, otherwise they could not be compared.
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
                    Text("Network").font(style.font(size: 15, weight: .semibold))
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
                if height < 150 {
                    HStack(spacing: 14) {
                        RateLabel(symbol: "arrow.down", color: style.accent,
                                  value: model.network.map { ByteFormat.rate($0.download) } ?? "–")
                        RateLabel(symbol: "arrow.up", color: uploadColor,
                                  value: model.network.map { ByteFormat.rate($0.upload) } ?? "–")
                        Spacer(minLength: 0)
                    }
                } else {
                VStack(spacing: 4) {
                    RateRow(symbol: "arrow.down", color: style.accent, title: "Download",
                            value: model.network.map { ByteFormat.rate($0.download) } ?? "–")
                    RateRow(symbol: "arrow.up", color: uploadColor, title: "Upload",
                            value: model.network.map { ByteFormat.rate($0.upload) } ?? "–")
                    RateRow(symbol: "clock.arrow.circlepath", color: .secondary, title: "Total",
                            value: "↓ \(ByteFormat.bytes(Double(model.networkTotal.received)))   ↑ \(ByteFormat.bytes(Double(model.networkTotal.sent)))")
                        .help("Since this tab was first opened")
                }
                }
            }
            .padding(14)
        }
    }
}

/// Display "numbers": download and upload as big figures, no history.
struct NetworkNumbersCard: View {
    let model: PerformanceModel
    let size: CGSize
    @Environment(\.shellStyle) private var style

    var body: some View {
        let stacked = size.height >= 200 && size.width < 420
        Card(radius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(style.font(size: 13, weight: .semibold))
                        .foregroundStyle(style.accent)
                    Text("Network").font(style.font(size: 15, weight: .semibold))
                }
                Spacer(minLength: 0)
                let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                                     : AnyLayout(HStackLayout(alignment: .bottom, spacing: 24))
                layout {
                    figure(symbol: "arrow.down", color: style.accent, title: "Download",
                           value: model.network?.download)
                    figure(symbol: "arrow.up", color: style.contrastAccent, title: "Upload",
                           value: model.network?.upload)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func figure(symbol: String, color: Color, title: LocalizedStringKey, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(style.font(size: 11, weight: .bold))
                    .foregroundStyle(color)
                Text(title).font(style.font(size: 12)).foregroundStyle(.secondary)
            }
            Text(value.map { ByteFormat.rate($0) } ?? "–")
                .font(.system(size: size.height >= 200 ? 34 : 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: value ?? 0))
                .animation(PerformanceAnimation.value, value: value)
        }
    }
}

private struct RateLabel: View {
    let symbol: String
    let color: Color
    let value: String
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(style.font(size: 11, weight: .bold))
                .foregroundStyle(color)
            Text(value).font(style.font(size: 13, weight: .medium)).monospacedDigit().lineLimit(1)
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

// MARK: - History line

/// A line with a lightly filled area below it (Caelestia: 15-20 % opacity).
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
        // The stroke should not look half cut off at the maximum at the top.
        .padding(.top, 1)
        .animation(PerformanceAnimation.value, value: scale)
    }
}

/// The scale can be animated: when the maximum jumps, the y axis glides along.
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
        // Softly over the midpoints, so that the peaks do not kink hard.
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

// MARK: - Battery

/// Caelestia BatteryTank: it fills from below like a liquid. The content lies
/// there twice - once normally, once in inverted colors masked onto the fill -
/// so that every bit of text stays readable, wherever the edge runs through it
/// right now.
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
                Text("Battery").font(style.font(size: 15, weight: .semibold))
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

/// Display "ring": the level on a ring, the state below it.
struct BatteryRingCard: View {
    let state: BatteryState
    let minutes: Int?
    let size: CGSize
    @Environment(\.shellStyle) private var style

    var body: some View {
        let wide = size.width > size.height * 1.3
        let ring = wide ? min(size.height - 32, 150) : min(size.width - 32, size.height - 70, 170)
        Card(radius: 24) {
            let dial = ZStack {
                Circle().stroke(Color.primary.opacity(0.10), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: Double(state.level) / 100)
                    .stroke(style.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(PerformanceAnimation.value, value: state.level)
                VStack(spacing: 0) {
                    Image(systemName: state.charging ? "bolt.fill" : (StatusGlyphs.batterySymbol(state) ?? "battery.100percent"))
                        .font(style.font(size: ring * 0.12, weight: .semibold))
                        .foregroundStyle(style.accent)
                    Text(BatteryTankText.percent(state))
                        .font(.system(size: ring * 0.22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .frame(width: ring, height: ring)
            let status = Text(BatteryTankText.status(state, minutes: minutes))
                .font(style.font(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(wide ? .leading : .center)
            if wide {
                HStack(spacing: 16) {
                    dial
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Battery").font(style.font(size: 15, weight: .semibold))
                        status
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 10) {
                    dial
                    status
                }
                .padding(12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StatusGlyphs.batteryText(state))
    }
}
