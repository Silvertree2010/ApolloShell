import ApolloShellCore
import SwiftUI

// Medien im Dashboard nach Caelestia (modules/dashboard/dash/Media.qml und
// modules/dashboard/Media.qml mit media/*), in Apple-Optik: SF Symbols statt
// Material-Icons, Systemschrift, Kapseln statt M3-Formen.
//
// Caelestias Zierrat, bewusst so entschieden:
// - Visualiser-Balken um das Cover (cava): weggelassen - dafuer braeuchte es
//   den Systemton, also eine Aufnahme-Freigabe.
// - Wellenlinie im Fortschritt, sich drehende Cookie-Form ums Cover,
//   treibende Formen im Hintergrund: weggelassen, sie wuerden bei jedem Bild
//   neu zeichnen. Statt der Formen liegt das Cover weichgezeichnet hinter dem
//   Reiter (wie Apple Musik), ruhig und nur einmal pro Cover gerechnet.
// - Bongo-Cat unter den Knoepfen: ersetzt durch die Quelle (App-Symbol und
//   Name), deren Wellen-Symbol animiert, solange etwas spielt.
// - Liedtexte und Player-Auswahl rechts im Reiter: es gibt keine Liedtexte,
//   und MediaRemote kennt nur eine aktive App - an ihrer Stelle die Quelle.

// MARK: - Bewegung

/// Caelestias Kurven und Dauern (plugin/src/Caelestia/Config/tokens.hpp).
enum MediaMotion {
    /// expressiveDefaultSpatial, 500 ms: Formwechsel und Druck der Knoepfe.
    static let spatial = Animation.shellSpatial
    /// expressiveDefaultEffects, 200 ms: Texte beim Titelwechsel.
    static let fade = Animation.timingCurve(0.34, 0.8, 0.34, 1, duration: 0.2)
    /// expressiveSlowEffects, 300 ms: "Nichts läuft" und Cover ueberblenden.
    static let slowFade = Animation.timingCurve(0.34, 0.88, 0.34, 1, duration: 0.3)
    /// StandardLarge, 600 ms: Fortschritt (Caelestia: Behavior on playerProgress).
    static let progress = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.6)
}

/// Akzent als Schriftfarbe. Caelestias primary ist im Hellen ein dunkler
/// Ton; die macOS-Akzentfarbe ist in beiden Schemata gleich, und Gelb auf
/// hellem Glas ist kaum lesbar (Bildprobe 14.09.). Im Hellen deshalb
/// abgedunkelt, im Dunklen pur.
/// Flaechen (Knopf, Bogen, Balken) bleiben pur, darauf steht `onAccent`.
enum MediaColor {
    static func accentText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .accentColor : Color.accentColor.mix(with: .black, by: 0.4)
    }
}

// MARK: - Karte im Raster

/// Karte rechts im Dashboard-Raster (200 x 392, Radius 56 wie Caelestia):
/// Cover im Kreis, oben ein halber Bogen als Fortschritt (Caelestia:
/// CircularProgress, 180 Grad, Strich 6), darunter Titel, Album, Kuenstler
/// und die drei Knoepfe.
struct MediaDashCard: View {
    let model: MediaModel
    /// Nexus > Dashboard; die Vorgabe zeigt alles wie bisher.
    var options = DashboardMediaOptions()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    /// Caelestia fuellt die Breite bis auf den Rand; unter den Knoepfen
    /// steht dort die Bongo-Cat. Ohne sie waere unten viel leer - der Bogen
    /// darf deshalb etwas groesser sein.
    private static let arcSize: CGFloat = 164
    private static let arcLine: CGFloat = 6
    /// Abstand Cover - Bogen (Caelestia: arcCoverGap = spacing.extraSmall).
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
        .accessibilityLabel("Medien")
    }

    /// Reihenfolge wie Caelestia: Titel (Akzent), Album (blass), Kuenstler.
    /// Ein fehlendes Album (Videos im Browser) faellt weg, statt
    /// "Unbekanntes Album" zu zeigen.
    @ViewBuilder private var texts: some View {
        VStack(spacing: 4) {
            if let playing = model.nowPlaying {
                Text(playing.title)
                    .font(style.font(size: 14, weight: .semibold))
                    .foregroundStyle(MediaColor.accentText(colorScheme))
                if options.showAlbum, let album = playing.album {
                    Text(album).font(style.font(size: 12)).foregroundStyle(.tertiary)
                }
                Text(playing.artist ?? String(localized: "Unbekannter Künstler"))
                    .font(style.font(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(model.isUnavailable ? String(localized: "Nicht verfügbar") : String(localized: "Nichts läuft"))
                    .font(style.font(size: 14, weight: .semibold))
                Text(model.isUnavailable ? String(localized: "Adapter läuft nicht") : String(localized: "Spiel etwas ab"))
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

/// Wiedergabe als Streifen: in der oberen Reihe (130 hoch) oder breit
/// gestreckt. Cover links so hoch wie die Karte, daneben Titel, Kuenstler,
/// Fortschritt und Knoepfe. Bei Caelestia steht die Karte nur rechts; so
/// passt sie auch in eine Reihe, und die Spalte wird frei.
struct MediaStripCard: View {
    let model: MediaModel
    var options = DashboardMediaOptions()
    /// Hoehe der Karte; das Cover fuellt sie bis auf den Rand.
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    private static let inset: CGFloat = 16

    var body: some View {
        // Hoechstens so gross wie das Cover im Reiter Medien.
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
        .accessibilityLabel("Medien")
    }

    @ViewBuilder private var texts: some View {
        if let playing = model.nowPlaying {
            Text(playing.title)
                .font(style.font(size: 14, weight: .semibold))
                .foregroundStyle(MediaColor.accentText(colorScheme))
            // Kuenstler und Album in einer Zeile: fuer zwei ist kein Platz.
            Text([playing.artist ?? String(localized: "Unbekannter Künstler"), options.showAlbum ? playing.album : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(style.font(size: 12))
                .foregroundStyle(.secondary)
        } else {
            Text(model.isUnavailable ? String(localized: "Nicht verfügbar") : String(localized: "Nichts läuft"))
                .font(style.font(size: 14, weight: .semibold))
            Text(model.isUnavailable ? String(localized: "Adapter läuft nicht") : String(localized: "Spiel etwas ab"))
                .font(style.font(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

/// Wiedergabe hochkant in einer Reihe (200 x 250): wie die Karte rechts,
/// nur kleiner - Bogen 112 statt 164, Titel und Kuenstler, die Knoepfe.
/// Album und Quelle fallen weg, dafuer reicht die Hoehe nicht.
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
                        Text(playing.artist ?? String(localized: "Unbekannter Künstler"))
                            .font(style.font(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(model.isUnavailable ? String(localized: "Nicht verfügbar") : String(localized: "Nichts läuft"))
                            .font(style.font(size: 13, weight: .semibold))
                        Text(model.isUnavailable ? String(localized: "Adapter läuft nicht") : String(localized: "Spiel etwas ab"))
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
        .accessibilityLabel("Medien")
    }
}

// MARK: - Reiter

/// Reiter "Medien", fuellt die Inhaltsflaeche des Dashboards (839 x 392).
/// Caelestia: 1000 x 320 mit drei Spalten - Cover (300), Details, Liedtexte
/// und Player-Auswahl (300), Abstand 28. Breiten mal 0,839, damit es passt;
/// die gewonnene Hoehe bekommt das Cover (244 statt 200).
struct MediaTab: View {
    let model: MediaModel
    @Environment(\.shellStyle) private var style

    private static let coverSection: CGFloat = 252  // 300 x 0,839
    private static let coverSize: CGFloat = 244
    private static let sourceWidth: CGFloat = 200
    /// Quelle genau so hoch wie das Cover: die Spalten bilden eine ruhige Linie.
    private static let panelHeight: CGFloat = coverSize
    private static let spacing: CGFloat = 24        // 28 x 0,839

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

/// Mittlere Spalte (Caelestia: media/Details.qml): Titel gross, Kuenstler,
/// Album; darunter Zeit mit Balken, darunter die Knoepfe.
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
            Text(playing.artist ?? String(localized: "Unbekannter Künstler"))
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

/// Abgespielt | Balken | Restzeit. Beide Zeiten stehen in der Breite der
/// laengsten moeglichen Anzeige (Caelestia: TextMetrics mit allen Ziffern
/// als 0), damit der Balken beim Zaehlen nicht zappelt und nichts gekuerzt
/// wird.
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
        .accessibilityLabel("\(MediaTime.clock(elapsed)) abgespielt")
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

/// Rechte Spalte statt Liedtexten und Player-Auswahl: welche App spielt.
private struct MediaSourcePanel: View {
    let source: MediaSource?
    let isPlaying: Bool
    @Environment(\.shellStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hifispeaker.fill").font(style.font(size: 14))
                Text("Quelle").font(style.font(size: 16, weight: .medium))
            }
            .padding(.leading, 6)
            Card(radius: 24) {
                VStack(spacing: 8) {
                    MediaAppIcon(icon: source?.icon, size: 64)
                    Text(source?.name ?? String(localized: "Unbekannte App"))
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

/// Caelestia: ClamShell-Form mit Symbol, "Nothing playing", Hinweis.
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
            Text(isUnavailable ? String(localized: "Medien nicht verfügbar") : String(localized: "Nichts läuft"))
                .font(style.font(size: 22, weight: .semibold))
            Text(isUnavailable ? String(localized: "Der Now-Playing-Adapter läuft nicht.") : String(localized: "Spiel etwas ab, dann erscheint es hier."))
                .font(style.font(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Bausteine

/// Tickt alle 0,5 s (Caelestia: mediaUpdateInterval 500), aber nur solange
/// etwas spielt - pausiert steht die Zeit ohnehin, und die Anzeige muss
/// nichts tun. Laeuft ueber die Bildschirm-Synchronisation, also auch nur,
/// solange das Fenster sichtbar ist.
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

/// Cover oder Platzhalter-Note; ein neues Cover blendet ueber. Als Overlay
/// auf der Form: so bestimmt die Form die Groesse, und ein breites Cover
/// (Video-Vorschau 16:9, gemessen 150 x 83 px) wird beschnitten statt den
/// Rahmen zu sprengen.
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

/// Weichgezeichnetes Cover hinter dem Reiter - ruhiger Ersatz fuer
/// Caelestias treibende Formen. Das Bild ist schon im Modell
/// weichgezeichnet (`MediaBlur`), einmal pro Cover; hier wird es nur
/// gestreckt. Im Hellen schwaecher, sonst leidet die graue Schrift.
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

/// Halber Bogen oben ums Cover, von links ueber oben nach rechts
/// (Caelestia: startAngle -90 - sweep/2, sweep 180). Gespielt in Akzent,
/// der Rest blass, mit Luecke dazwischen wie dort.
private struct MediaArc: View {
    let value: Double
    let lineWidth: CGFloat
    @Environment(\.shellStyle) private var style

    /// Luecke als Anteil des Umfangs; deckt die runden Enden mit ab.
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
        // Der Kreis beginnt rechts; um 180 Grad gedreht faengt er links an
        // und fuellt ueber oben nach rechts.
        .rotationEffect(.degrees(180))
        .animation(MediaMotion.progress, value: played)
        .accessibilityHidden(true)
    }
}

/// Fortschrittsbalken; ohne bekannte Laenge (Livestream) nur die Spur.
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

/// Zurueck, Wiedergabe/Pause (breit), Weiter - wie Caelestias ButtonRow.
/// Spielt etwas, ist der mittlere Knopf gefuellt und eckiger (Caelestia:
/// checked + shapeMorph), pausiert rund und getoent.
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
            MediaRoundButton(symbol: "backward.fill", label: "Vorheriger Titel", size: height, symbolSize: symbolSize) {
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
            .help(playing ? "Pause" : "Wiedergabe")
            .accessibilityLabel(playing ? "Pause" : "Wiedergabe")
            MediaRoundButton(symbol: "forward.fill", label: "Nächster Titel", size: height, symbolSize: symbolSize) {
                model.send(.nextTrack)
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .animation(MediaMotion.spatial, value: playing)
    }
}

/// Runder, getoenter Knopf (Caelestia: IconButton Tonal, isRound).
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

/// Druck: kurz kleiner, federt mit Caelestias Raumkurve zurueck.
private struct MediaPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(MediaMotion.spatial, value: configuration.isPressed)
    }
}

/// Quelle als Kapsel unten in der Karte (anstelle von Caelestias Bongo-Cat).
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
        .help("Spielt in \(source.name)")
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

/// Wellen, die laufen, solange etwas spielt; sonst Pause-Zeichen.
private struct MediaPlayState: View {
    let isPlaying: Bool
    var showsText = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isPlaying ? "waveform" : "pause.fill")
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                .contentTransition(.symbolEffect(.replace))
            if showsText {
                Text(isPlaying ? String(localized: "Spielt gerade") : String(localized: "Pausiert"))
            }
        }
    }
}
