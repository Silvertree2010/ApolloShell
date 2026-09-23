import ApolloShellCore
import SwiftUI

/// The now-playing card in the utilities panel: a small cover, title and
/// artist, and the transport buttons - one row, reusing the same building
/// blocks as the Dashboard's media cards (`MediaView.swift`: `MediaArtwork`,
/// `MediaControls`, `MediaColor`), only compact enough to fit
/// `UtilitiesMetrics.nowPlayingHeight`.
///
/// The stream (`MediaModel`) is started while the utilities panel is open
/// and stopped when it closes (`UtilitiesPanel.swift`), the same way
/// `Dashboard.swift` runs it only while the Dashboard is open.
struct UtilitiesNowPlayingCard: View {
    let model: MediaModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    /// Square cover side for music; a video's picture keeps this height at
    /// 16:9 instead.
    private static let cover: CGFloat = 48

    var body: some View {
        UtilitiesCard {
            HStack(spacing: 12) {
                artwork
                texts
                    .frame(maxWidth: .infinity, alignment: .leading)
                MediaControls(model: model, height: 28, symbolSize: 12, spacing: 4)
                    .frame(width: 108)
            }
            .animation(MediaMotion.slowFade, value: model.nowPlaying == nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now Playing")
    }

    @ViewBuilder private var artwork: some View {
        if model.kind == .video {
            MediaArtwork(image: model.artwork, id: model.artworkID,
                        shape: RoundedRectangle(cornerRadius: style.cardRadius(8), style: .continuous),
                        symbolSize: 16, placeholder: "play.rectangle")
                .frame(width: (Self.cover * 16 / 9).rounded(), height: Self.cover)
        } else {
            MediaArtwork(image: model.artwork, id: model.artworkID,
                        shape: RoundedRectangle(cornerRadius: style.cardRadius(10), style: .continuous), symbolSize: 16)
                .frame(width: Self.cover, height: Self.cover)
        }
    }

    @ViewBuilder private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
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
        .contentTransition(.opacity)
        .animation(MediaMotion.fade, value: model.nowPlaying?.title)
    }
}
