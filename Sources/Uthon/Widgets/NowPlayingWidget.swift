import SwiftUI

struct NowPlayingWidget: View {
    @ObservedObject private var player = NowPlayingStore.shared

    var body: some View {
        Card("Now Playing", symbol: "music.note") {
            if let track = player.track {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.accent.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: track.isPlaying ? "waveform" : "pause.fill")
                                .foregroundStyle(Theme.accent)
                                .symbolEffect(.variableColor.iterative, isActive: track.isPlaying)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist.isEmpty ? track.player : track.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 22) {
                    Spacer()
                    control("backward.fill") { player.command("previous track") }
                    control(track.isPlaying ? "pause.fill" : "play.fill", size: 18) { player.command("playpause") }
                    control("forward.fill") { player.command("next track") }
                    Spacer()
                }
            } else {
                HStack {
                    Text("Nothing playing")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Button("Open Music") { player.openMusic() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func control(_ symbol: String, size: CGFloat = 13, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
    }
}
