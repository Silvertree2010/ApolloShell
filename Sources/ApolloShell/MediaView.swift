import ApolloShellCore
import SwiftUI

// Media in the dashboard, following Caelestia (modules/dashboard/dash/
// Media.qml and modules/dashboard/Media.qml with media/*), but in Apple
// styling: SF Symbols instead of Material icons, system font, capsules
// instead of M3 shapes.
//
// Caelestia's decorations, left out on purpose:
// - Visualiser bars around the cover (cava): omitted - that would need
//   system audio, i.e. a recording permission.
// - Wavy progress line, rotating cookie shape around the cover, drifting
//   shapes in the background: omitted, they would redraw on every frame.
//   Instead of the shapes, the cover sits blurred behind the tab (like
//   Apple Music), calm and computed only once per cover.
// - Bongo cat below the buttons: replaced by the source (app icon and
//   name), whose waveform symbol animates while something is playing.
// - Lyrics and player picker on the right of the tab: there are no
//   lyrics, and MediaRemote only knows one active app - the source takes
//   their place.

// MARK: - Motion

/// Caelestia's curves and durations (plugin/src/Caelestia/Config/
/// tokens.hpp).
enum MediaMotion {
    /// expressiveDefaultSpatial, 500 ms: shape changes and button press.
    static let spatial = Animation.shellSpatial
    /// expressiveDefaultEffects, 200 ms: text on title change.
    static let fade = Animation.timingCurve(0.34, 0.8, 0.34, 1, duration: 0.2)
    /// expressiveSlowEffects, 300 ms: "Nothing playing" and cover crossfade.
    static let slowFade = Animation.timingCurve(0.34, 0.88, 0.34, 1, duration: 0.3)
    /// StandardLarge, 600 ms: progress (Caelestia: Behavior on playerProgress).
    static let progress = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.6)
}

/// Accent as text color. Caelestia's primary is a dark tone in light mode;
/// the macOS accent color is the same in both schemes, and yellow on light
/// glass is barely readable (visual check 14.09.). Darkened in light mode
/// for that reason, pure in dark mode.
/// Filled shapes (button, arc, bar) stay pure, `onAccent` sits on top of them.
enum MediaColor {
    static func accentText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .accentColor : Color.accentColor.mix(with: .black, by: 0.4)
    }
}

// MARK: - Card in the grid

/// Card on the right of the dashboard grid (200 x 392, radius 56 like
/// Caelestia): cover in a circle, a half arc on top as progress
/// (Caelestia: CircularProgress, 180 degrees, stroke 6), below it title,
/// album, artist and the three buttons.
struct MediaDashCard: View {
    let model: MediaModel
    /// Nexus > Dashboard; the default shows everything as before.
    var options = DashboardMediaOptions()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    /// Caelestia fills the width all the way to the edge; the bongo cat
    /// sits below the buttons there. Without it, the bottom would be quite
    /// empty - so the arc may be a bit larger.
    private static let arcSize: CGFloat = 164
    private static let arcLine: CGFloat = 6
    /// Gap cover - arc (Caelestia: arcCoverGap = spacing.extraSmall).
    private static let arcGap: CGFloat = 4

    var body: some View {
        Card(radius: 56) {
            VStack(spacing: 0) {
                MediaClock(model: model) { now in
                    ZStack {
                        MediaArc(value: model.nowPlaying?.progress(at: now) ?? 0, lineWidth: Self.arcLine)
                        MediaArtwork(image: model.artwork, id: model.artworkID, shape: Circle(), symbolSize: 40)
                            .padding(Self.arcLine + Self.arcGap)
                    }
                }
                .frame(width: Self.arcSize, height: Self.arcSize)
                .padding(.top, 22)

                texts
                    .frame(width: 168)
                    .padding(.top, 14)

                MediaControls(model: model, height: 40, symbolSize: 15, spacing: 4)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                Spacer(minLength: 0)

                if options.showSource, let source = model.source, let playing = model.nowPlaying {
                    MediaSourceChip(source: source, isPlaying: playing.isPlaying)
                        .frame(maxWidth: 168)
                        .padding(.bottom, 22)
                        .transition(.opacity)
                }
            }
            .animation(MediaMotion.slowFade, value: model.nowPlaying == nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media")
    }

    /// Order as in Caelestia: title (accent), album (faint), artist. A
    /// missing album (browser videos) is simply left out instead of
    /// showing "Unknown Album".
    @ViewBuilder private var texts: some View {
        VStack(spacing: 4) {
            if let playing = model.nowPlaying {
                Text(playing.title)
                    .font(style.font(size: 14, weight: .semibold))
                    .foregroundStyle(MediaColor.accentText(colorScheme))
                if options.showAlbum, let album = playing.album {
                    Text(album).font(style.font(size: 12)).foregroundStyle(.tertiary)
                }
                Text(playing.artist ?? String(localized: "Unknown Artist"))
                    .font(style.font(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(model.isUnavailable ? String(localized: "Not Available") : String(localized: "Nothing Playing"))
                    .font(style.font(size: 14, weight: .semibold))
                Text(model.isUnavailable ? String(localized: "Adapter Not Running") : String(localized: "Play Something"))
                    .font(style.font(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .contentTransition(.opacity)
        .animation(MediaMotion.fade, value: model.nowPlaying?.title)
    }
}

/// Playback as a strip: in the top row (130 tall) or stretched wide. Cover
/// on the left, as tall as the card, next to it title, artist, progress
/// and buttons. In Caelestia the card only exists on the right; this way
/// it also fits into a row, and the column becomes free.
struct MediaStripCard: View {
    let model: MediaModel
    var options = DashboardMediaOptions()
    /// Height of the card; the cover fills it up to the edge.
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    private static let inset: CGFloat = 16

    var body: some View {
        // At most as large as the cover in the Media tab.
        let cover = min(max(height - 2 * Self.inset, 40), 244)
        Card(radius: 28) {
            HStack(spacing: 16) {
                MediaArtwork(image: model.artwork, id: model.artworkID,
                             shape: RoundedRectangle(cornerRadius: style.cardRadius(18), style: .continuous), symbolSize: cover * 0.32)
                    .frame(width: cover, height: cover)
                VStack(alignment: .leading, spacing: 3) {
                    texts
                    MediaClock(model: model) { now in
                        MediaProgressBar(value: model.nowPlaying?.progress(at: now) ?? 0,
                                         known: model.nowPlaying?.duration != nil)
                    }
                    .padding(.top, 6)
                    MediaControls(model: model, height: 34, symbolSize: 13, spacing: 4)
                        .frame(maxWidth: 200)
                        .padding(.top, 8)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
                .animation(MediaMotion.fade, value: model.nowPlaying?.title)
            }
            .padding(Self.inset)
        }
        .animation(MediaMotion.slowFade, value: model.nowPlaying == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media")
    }

    @ViewBuilder private var texts: some View {
        if let playing = model.nowPlaying {
            Text(playing.title)
                .font(style.font(size: 14, weight: .semibold))
                .foregroundStyle(MediaColor.accentText(colorScheme))
            // Artist and album in one line: there is no room for two.
            Text([playing.artist ?? String(localized: "Unknown Artist"), options.showAlbum ? playing.album : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(style.font(size: 12))
                .foregroundStyle(.secondary)
        } else {
            Text(model.isUnavailable ? String(localized: "Not Available") : String(localized: "Nothing Playing"))
                .font(style.font(size: 14, weight: .semibold))
            Text(model.isUnavailable ? String(localized: "Adapter Not Running") : String(localized: "Play Something"))
                .font(style.font(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

/// Playback in portrait in a row (200 x 250): like the card on the right,
/// only smaller - arc 112 instead of 164, title and artist, the buttons.
/// Album and source are left out, the height isn't enough for them.
struct MediaCompactCard: View {
    let model: MediaModel
    var options = DashboardMediaOptions()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    private static let arcSize: CGFloat = 112
    private static let arcLine: CGFloat = 5
    private static let arcGap: CGFloat = 4

    var body: some View {
        Card(radius: 40) {
            VStack(spacing: 0) {
                MediaClock(model: model) { now in
                    ZStack {
                        MediaArc(value: model.nowPlaying?.progress(at: now) ?? 0, lineWidth: Self.arcLine)
                        MediaArtwork(image: model.artwork, id: model.artworkID, shape: Circle(), symbolSize: 28)
                            .padding(Self.arcLine + Self.arcGap)
                    }
                }
                .frame(width: Self.arcSize, height: Self.arcSize)

                VStack(spacing: 2) {
                    if let playing = model.nowPlaying {
                        Text(playing.title)
                            .font(style.font(size: 13, weight: .semibold))
                            .foregroundStyle(MediaColor.accentText(colorScheme))
                        Text(playing.artist ?? String(localized: "Unknown Artist"))
                            .font(style.font(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(model.isUnavailable ? String(localized: "Not Available") : String(localized: "Nothing Playing"))
                            .font(style.font(size: 13, weight: .semibold))
                        Text(model.isUnavailable ? String(localized: "Adapter Not Running") : String(localized: "Play Something"))
                            .font(style.font(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: 168)
                .padding(.top, 10)
                .contentTransition(.opacity)
                .animation(MediaMotion.fade, value: model.nowPlaying?.title)

                MediaControls(model: model, height: 34, symbolSize: 13, spacing: 4)
                    .frame(maxWidth: 168)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 16)
        }
        .animation(MediaMotion.slowFade, value: model.nowPlaying == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media")
    }
}

// MARK: - Tab

/// The "Media" tab, fills the dashboard's content area (839 x 392).
/// Caelestia: 1000 x 320 with three columns - cover (300), details, lyrics
/// and player picker (300), gap 28. Widths times 0.839 to make it fit; the
/// extra height goes to the cover (244 instead of 200).
struct MediaTab: View {
    let model: MediaModel
    @Environment(\.shellStyle) private var style

    private static let coverSection: CGFloat = 252  // 300 x 0.839
    private static let coverSize: CGFloat = 244
    private static let sourceWidth: CGFloat = 200
    /// Source exactly as tall as the cover: the columns form a calm line.
    private static let panelHeight: CGFloat = coverSize
    private static let spacing: CGFloat = 24        // 28 x 0.839

    var body: some View {
        HStack(spacing: Self.spacing) {
            MediaArtwork(image: model.artwork, id: model.artworkID,
                         shape: RoundedRectangle(cornerRadius: style.cardRadius(28), style: .continuous), symbolSize: 64)
                .frame(width: Self.coverSize, height: Self.coverSize)
                .shadow(color: .black.opacity(model.artwork == nil ? 0 : 0.3), radius: 18, y: 8)
                .frame(width: Self.coverSection)

            ZStack {
                if let playing = model.nowPlaying {
                    HStack(spacing: Self.spacing) {
                        MediaDetails(model: model, playing: playing)
                        MediaSourcePanel(source: model.source, isPlaying: playing.isPlaying)
                            .frame(width: Self.sourceWidth, height: Self.panelHeight)
                    }
                    .transition(.opacity)
                } else {
                    MediaNothingPlaying(isUnavailable: model.isUnavailable)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.leading, 18)
        .padding(.trailing, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { MediaAmbient(image: model.ambient, id: model.artworkID) }
        .animation(MediaMotion.slowFade, value: model.nowPlaying == nil)
    }
}

/// Middle column (Caelestia: media/Details.qml): title large, artist,
/// album; below that time with a bar, below that the buttons.
private struct MediaDetails: View {
    let model: MediaModel
    let playing: MediaNowPlaying
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playing.title)
                .font(style.font(size: 22, weight: .semibold))
                .lineLimit(2)
            Text(playing.artist ?? String(localized: "Unknown Artist"))
                .font(style.font(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            if let album = playing.album {
                Text(album)
                    .font(style.font(size: 16, weight: .medium))
                    .foregroundStyle(MediaColor.accentText(colorScheme))
            }

            MediaClock(model: model) { now in
                MediaTimeline(playing: playing, now: now)
            }
            .padding(.top, 26)

            MediaControls(model: model, height: 52, symbolSize: 20, spacing: 6)
                .padding(.top, 18)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentTransition(.opacity)
        .animation(MediaMotion.fade, value: playing.title)
    }
}

/// Elapsed | bar | remaining. Both times are given the width of the
/// longest possible display (Caelestia: TextMetrics with all digits as 0),
/// so the bar doesn't jitter while counting and nothing gets clipped.
private struct MediaTimeline: View {
    let playing: MediaNowPlaying
    let now: Date
    @Environment(\.shellStyle) private var style

    var body: some View {
        let elapsed = playing.elapsed(at: now) ?? 0
        let template = String(MediaTime.clock(playing.duration ?? elapsed).map { $0.isNumber ? "0" : $0 })
        HStack(spacing: 10) {
            MediaTimeLabel(text: MediaTime.clock(elapsed), template: template)
            MediaProgressBar(value: playing.progress(at: now), known: playing.duration != nil)
            MediaTimeLabel(
                text: playing.duration.map { MediaTime.remaining(elapsed: elapsed, duration: $0) } ?? MediaTime.unknown,
                template: "-" + template
            )
        }
        .font(style.font(size: 12, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(MediaTime.clock(elapsed)) elapsed")
    }
}

private struct MediaTimeLabel: View {
    let text: String
    let template: String

    var body: some View {
        ZStack {
            Text(template).hidden()
            Text(text)
        }
        .fixedSize()
    }
}

/// Right column instead of lyrics and player picker: which app is playing.
private struct MediaSourcePanel: View {
    let source: MediaSource?
    let isPlaying: Bool
    @Environment(\.shellStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hifispeaker.fill").font(style.font(size: 14))
                Text("Source").font(style.font(size: 16, weight: .medium))
            }
            .padding(.leading, 6)
            Card(radius: 24) {
                VStack(spacing: 8) {
                    MediaAppIcon(icon: source?.icon, size: 64)
                    Text(source?.name ?? String(localized: "Unknown App"))
                        .font(style.font(size: 15, weight: .semibold))
                        .lineLimit(1)
                    MediaPlayState(isPlaying: isPlaying)
                        .font(style.font(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Caelestia: ClamShell shape with icon, "Nothing playing", hint.
private struct MediaNothingPlaying: View {
    let isUnavailable: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isUnavailable ? "exclamationmark.triangle" : "music.note.list")
                .font(style.font(size: 40, weight: .medium))
                .foregroundStyle(MediaColor.accentText(colorScheme))
                .frame(width: 96, height: 96)
                .background(style.accent.opacity(0.16), in: .rect(cornerRadius: style.cardRadius(30), style: .continuous))
                .padding(.bottom, 8)
            Text(isUnavailable ? String(localized: "Media Not Available") : String(localized: "Nothing Playing"))
                .font(style.font(size: 22, weight: .semibold))
            Text(isUnavailable ? String(localized: "The Now Playing adapter isn't running.") : String(localized: "Play something, and it will appear here."))
                .font(style.font(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Building blocks

/// Ticks every 0.5 s (Caelestia: mediaUpdateInterval 500), but only while
/// something is playing - when paused the time stands still anyway, and
/// the display has nothing to do. Runs on the screen sync, so it also only
/// runs while the window is visible.
private struct MediaClock<Content: View>: View {
    let model: MediaModel
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        let paused = !(model.nowPlaying?.isPlaying ?? false) || model.fixedNow != nil
        TimelineView(.animation(minimumInterval: 0.5, paused: paused)) { context in
            content(model.fixedNow ?? context.date)
        }
    }
}

/// Cover or a placeholder note; a new cover crossfades in. As an overlay
/// on the shape: this way the shape determines the size, and a wide cover
/// (video preview 16:9, measured 150 x 83 px) is cropped instead of
/// breaking out of the frame.
private struct MediaArtwork<S: Shape>: View {
    let image: NSImage?
    let id: Int
    let shape: S
    let symbolSize: CGFloat

    var body: some View {
        shape
            .fill(Color.primary.opacity(0.08))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: symbolSize, weight: .light))
                    .foregroundStyle(.tertiary)
                    .opacity(image == nil ? 1 : 0)
            }
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .id(id)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .animation(MediaMotion.slowFade, value: id)
            .accessibilityHidden(true)
    }
}

/// Blurred cover behind the tab - a calm replacement for Caelestia's
/// drifting shapes. The image is already blurred in the model
/// (`MediaBlur`), once per cover; here it is only stretched. Weaker in
/// light mode, otherwise the gray text suffers.
private struct MediaAmbient: View {
    let image: NSImage?
    let id: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    var body: some View {
        Color.primary.opacity(0.06)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .opacity(colorScheme == .dark ? 0.45 : 0.35)
                        .id(id)
                        .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: style.cardRadius(28), style: .continuous))
            .animation(MediaMotion.slowFade, value: id)
    }
}

/// Half arc above the cover, from left over the top to the right
/// (Caelestia: startAngle -90 - sweep/2, sweep 180). Played portion in
/// accent, the rest faint, with a gap between them as there.
private struct MediaArc: View {
    let value: Double
    let lineWidth: CGFloat
    @Environment(\.shellStyle) private var style

    /// Gap as a fraction of the circumference; also covers the round ends.
    private let gap = 0.03

    var body: some View {
        let played = 0.5 * min(max(value, 0), 1)
        let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: min(played + gap, 0.5), to: 0.5)
                .stroke(Color.primary.opacity(0.12), style: strokeStyle)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: played)
                .stroke(style.accent, style: strokeStyle)
        }
        // The circle starts on the right; rotated 180 degrees it starts on
        // the left and fills over the top toward the right.
        .rotationEffect(.degrees(180))
        .animation(MediaMotion.progress, value: played)
        .accessibilityHidden(true)
    }
}

/// Progress bar; only the track without a known length (livestream).
private struct MediaProgressBar: View {
    let value: Double
    let known: Bool
    @Environment(\.shellStyle) private var style

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                if known {
                    Capsule()
                        .fill(style.accent)
                        .frame(width: max(geometry.size.height, geometry.size.width * min(max(value, 0), 1)))
                }
            }
        }
        .frame(height: 6)
        .animation(MediaMotion.progress, value: value)
    }
}

/// Previous, play/pause (wide), next - like Caelestia's ButtonRow. While
/// something is playing, the middle button is filled and more angular
/// (Caelestia: checked + shapeMorph), paused it's round and tinted.
private struct MediaControls: View {
    let model: MediaModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style
    let height: CGFloat
    let symbolSize: CGFloat
    let spacing: CGFloat

    var body: some View {
        let playing = model.nowPlaying?.isPlaying ?? false
        let enabled = model.nowPlaying != nil
        HStack(spacing: spacing) {
            MediaRoundButton(symbol: "backward.fill", label: "Previous Track", size: height, symbolSize: symbolSize) {
                model.send(.previousTrack)
            }
            Button {
                model.send(.togglePlayPause)
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: symbolSize + 2, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(playing ? style.onAccent : MediaColor.accentText(colorScheme))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(playing ? style.accent : style.accent.opacity(0.16),
                                in: .rect(cornerRadius: playing ? height * 0.32 : height / 2, style: .continuous))
                    .contentShape(.rect)
            }
            .buttonStyle(MediaPressStyle())
            .help(playing ? "Pause" : "Play")
            .accessibilityLabel(playing ? "Pause" : "Play")
            MediaRoundButton(symbol: "forward.fill", label: "Next Track", size: height, symbolSize: symbolSize) {
                model.send(.nextTrack)
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .animation(MediaMotion.spatial, value: playing)
    }
}

/// Round, tinted button (Caelestia: IconButton Tonal, isRound).
private struct MediaRoundButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let size: CGFloat
    let symbolSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background(Color.primary.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(MediaPressStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Press: briefly smaller, springs back with Caelestia's spatial curve.
private struct MediaPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(MediaMotion.spatial, value: configuration.isPressed)
    }
}

/// Source as a capsule at the bottom of the card (in place of Caelestia's
/// bongo cat).
private struct MediaSourceChip: View {
    let source: MediaSource
    let isPlaying: Bool
    @Environment(\.shellStyle) private var style

    var body: some View {
        HStack(spacing: 6) {
            MediaAppIcon(icon: source.icon, size: 18)
            Text(source.name)
                .font(style.font(size: 11, weight: .medium))
                .lineLimit(1)
            MediaPlayState(isPlaying: isPlaying, showsText: false)
                .font(style.font(size: 10, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.07), in: .capsule)
        .help("Playing in \(source.name)")
    }
}

private struct MediaAppIcon: View {
    let icon: NSImage?
    let size: CGFloat

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.7, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

/// Waves that run while something is playing; a pause icon otherwise.
private struct MediaPlayState: View {
    let isPlaying: Bool
    var showsText = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isPlaying ? "waveform" : "pause.fill")
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                .contentTransition(.symbolEffect(.replace))
            if showsText {
                Text(isPlaying ? String(localized: "Playing") : String(localized: "Paused"))
            }
        }
    }
}
