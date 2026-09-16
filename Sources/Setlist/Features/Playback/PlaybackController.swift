import AVFoundation
import Foundation

@MainActor
final class PlaybackController: NSObject, ObservableObject {
    @Published private(set) var currentTrack: LocalTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var waveform: [Float] = []
    @Published private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var scopedFolderURL: URL?
    private var waveformTask: Task<Void, Never>?

    func toggle(track: LocalTrack, locations: [MusicLocation]) {
        if currentTrack?.path == track.path {
            togglePlayback()
        } else {
            loadAndPlay(track: track, locations: locations)
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            progressTimer?.invalidate()
            progressTimer = nil
        } else {
            isPlaying = player.play()
            if isPlaying { startProgressTimer() }
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(time, 0), duration)
        currentTime = player.currentTime
    }

    func stop() {
        waveformTask?.cancel()
        waveformTask = nil
        player?.stop()
        player = nil
        progressTimer?.invalidate()
        progressTimer = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        waveform = []
        currentTrack = nil
        releaseFolderAccess()
    }

    func dismissError() {
        errorMessage = nil
    }

    private func loadAndPlay(track: LocalTrack, locations: [MusicLocation]) {
        stop()
        errorMessage = nil
        let fileURL = URL(fileURLWithPath: track.path)

        do {
            try accessApprovedLocation(containing: fileURL, locations: locations)
            let newPlayer = try AVAudioPlayer(contentsOf: fileURL)
            newPlayer.prepareToPlay()
            player = newPlayer
            currentTrack = track
            duration = newPlayer.duration
            startProgressTimer()
            guard newPlayer.play() else { throw PlaybackError.couldNotStartPlayback }
            isPlaying = true
            loadWaveform(for: fileURL)
        } catch {
            stop()
            errorMessage = "Setlist could not play this local file. \(error.localizedDescription)"
        }
    }

    private func accessApprovedLocation(containing fileURL: URL, locations: [MusicLocation]) throws {
        guard let location = locations
            .filter({ fileURL.path.hasPrefix($0.path + "/") || fileURL.path == $0.path })
            .max(by: { $0.path.count < $1.path.count }) else {
            throw PlaybackError.fileOutsideApprovedLocations
        }

        guard location.usesSecurityScope else { return }
        var isStale = false
        let folderURL = try URL(
            resolvingBookmarkData: location.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale, folderURL.startAccessingSecurityScopedResource() else {
            throw PlaybackError.reapproveLocation(location.displayName)
        }
        scopedFolderURL = folderURL
    }

    private func releaseFolderAccess() {
        scopedFolderURL?.stopAccessingSecurityScopedResource()
        scopedFolderURL = nil
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying, self.currentTime >= self.duration - 0.05 {
                    self.isPlaying = false
                    self.currentTime = self.duration
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                }
            }
        }
    }

    private func loadWaveform(for fileURL: URL) {
        waveformTask?.cancel()
        waveform = []
        waveformTask = Task.detached(priority: .utility) { [weak self] in
            let samples = WaveformGenerator.samples(for: fileURL, bucketCount: 96)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard self?.currentTrack?.path == fileURL.path else { return }
                self?.waveform = samples
            }
        }
    }
}

private enum PlaybackError: LocalizedError {
    case fileOutsideApprovedLocations
    case reapproveLocation(String)
    case couldNotStartPlayback

    var errorDescription: String? {
        switch self {
        case .fileOutsideApprovedLocations:
            "This file is no longer inside an approved music location."
        case let .reapproveLocation(name):
            "Please approve \(name) again in Music locations."
        case .couldNotStartPlayback:
            "This audio file could not be started."
        }
    }
}

enum WaveformGenerator {
    static func samples(for url: URL, bucketCount: Int) -> [Float] {
        guard bucketCount > 0,
              let file = try? AVAudioFile(forReading: url),
              file.length > 0 else { return [] }

        let framesPerBucket = max(1, Int(file.length) / bucketCount)
        // Inspect each portion of the audio, while capping per-bucket CPU work
        // so long tracks do not make preview interaction feel sluggish.
        let sampleStride = max(1, framesPerBucket / 256)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8_192)!
        var buckets = Array(repeating: Float.zero, count: bucketCount)
        var peak: Float = 0

        while file.framePosition < file.length {
            guard !Task.isCancelled else { return [] }
            let startFrame = file.framePosition
            do {
                try file.read(into: buffer)
            } catch {
                return []
            }
            guard let channelData = buffer.floatChannelData else { return [] }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }

            for offset in stride(from: 0, to: frameLength, by: sampleStride) {
                let absoluteFrame = startFrame + AVAudioFramePosition(offset)
                let bucketIndex = min(bucketCount - 1, Int((absoluteFrame * AVAudioFramePosition(bucketCount)) / file.length))
                for channel in 0..<Int(buffer.format.channelCount) {
                    buckets[bucketIndex] = max(buckets[bucketIndex], abs(channelData[channel][offset]))
                }
                peak = max(peak, buckets[bucketIndex])
            }
        }

        guard peak > 0 else { return [] }
        return buckets.map { max(0.12, $0 / peak) }
    }
}
