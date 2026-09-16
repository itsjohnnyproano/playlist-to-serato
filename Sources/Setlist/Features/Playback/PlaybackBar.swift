import SwiftUI

struct PlaybackBar: View {
    @EnvironmentObject private var playback: PlaybackController

    var body: some View {
        if let track = playback.currentTrack {
            HStack(spacing: 18) {
                Button {
                    playback.togglePlayback()
                } label: {
                    PlayPauseIcon(isPlaying: playback.isPlaying, size: 17)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.setlistBlue.gradient, in: Circle())
                        .shadow(color: Color.setlistBlue.opacity(0.32), radius: 8, y: 3)
                        .contentShape(Circle())
                }
                .buttonStyle(PreviewControlButtonStyle())
                .accessibilityLabel(playback.isPlaying ? "Pause preview" : "Play preview")

                VStack(alignment: .leading, spacing: 4) {
                    Text("NOW PREVIEWING")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(track.title).fontWeight(.semibold).lineLimit(1)
                    Text(track.artist.isEmpty ? track.sourceFolder : track.artist)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 210, alignment: .leading)

                Text(timeText(playback.currentTime))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)

                WaveformScrubber(samples: playback.waveform, progress: progress) { value in
                    playback.seek(to: value * playback.duration)
                }
                .frame(minWidth: 180, maxWidth: .infinity)

                Text(timeText(playback.duration))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)

                Button {
                    playback.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(.quaternary, in: Circle())
                .accessibilityLabel("Close preview")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.48), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 22, y: 8)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: 1_150)
        }
    }

    private var progress: Double {
        guard playback.duration > 0 else { return 0 }
        return playback.currentTime / playback.duration
    }

    private func timeText(_ time: TimeInterval) -> String {
        Duration.seconds(time).formatted(.time(pattern: .minuteSecond))
    }
}

struct PlayPauseIcon: View {
    let isPlaying: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Image(systemName: "play.fill")
                .opacity(isPlaying ? 0 : 1)
                .scaleEffect(isPlaying ? 0.72 : 1)
                .offset(y: isPlaying ? -1.5 : 0)
            Image(systemName: "pause.fill")
                .opacity(isPlaying ? 1 : 0)
                .scaleEffect(isPlaying ? 1 : 0.72)
                .offset(y: isPlaying ? 0 : 1.5)
        }
        .font(.system(size: size, weight: .bold))
        .animation(.easeInOut(duration: 0.13), value: isPlaying)
    }
}

struct PreviewControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.linear(duration: 0.07), value: configuration.isPressed)
    }
}

private struct WaveformScrubber: View {
    let samples: [Float]
    let progress: Double
    let seek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let bars = samples.isEmpty ? Array(repeating: Float(0.25), count: 52) : samples
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { index, sample in
                        Capsule()
                            .fill(Double(index) / Double(max(bars.count - 1, 1)) <= progress ? Color.setlistBlue : Color.secondary.opacity(0.25))
                            .frame(height: max(4, CGFloat(sample) * proxy.size.height))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Capsule()
                    .fill(Color.primary.opacity(0.72))
                    .frame(width: 2, height: proxy.size.height + 8)
                    .offset(x: min(max(progress * proxy.size.width, 1), proxy.size.width - 1))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                seek(min(max(value.location.x / proxy.size.width, 0), 1))
            })
        }
        .frame(height: 30)
        .accessibilityLabel("Track progress")
    }
}
