import Foundation

struct LocalTrack: Identifiable, Codable, Hashable {
    let id: UUID
    var path: String
    var artist: String
    var title: String
    var fileType: String
    var duration: TimeInterval?
    var sourceFolder: String

    init(path: String, artist: String, title: String, fileType: String, duration: TimeInterval?, sourceFolder: String) {
        id = UUID()
        self.path = path
        self.artist = artist
        self.title = title
        self.fileType = fileType
        self.duration = duration
        self.sourceFolder = sourceFolder
    }
}

@MainActor
final class TrackIndexStore: ObservableObject {
    @Published private(set) var tracks: [LocalTrack] = []
    @Published private(set) var lastScannedAt: Date?

    init() {
        let saved = try? LocalStorage.load(TrackIndexSnapshot.self, named: "local-track-index.json")
        tracks = saved?.tracks ?? []
        lastScannedAt = saved?.lastScannedAt
    }

    func replace(with tracks: [LocalTrack]) throws {
        let scannedAt = Date.now
        try LocalStorage.save(TrackIndexSnapshot(tracks: tracks, lastScannedAt: scannedAt), named: "local-track-index.json")
        self.tracks = tracks
        lastScannedAt = scannedAt
    }
}

private struct TrackIndexSnapshot: Codable {
    var tracks: [LocalTrack]
    var lastScannedAt: Date?
}
