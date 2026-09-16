import Foundation

struct LocalTrack: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var path: String
    var artist: String
    var title: String
    var fileType: String
    var duration: TimeInterval?
    var bitrateKbps: Int?
    var sourceFolder: String

    init(path: String, artist: String, title: String, fileType: String, duration: TimeInterval?, bitrateKbps: Int? = nil, sourceFolder: String) {
        id = UUID()
        self.path = path
        self.artist = artist
        self.title = title
        self.fileType = fileType
        self.duration = duration
        self.bitrateKbps = bitrateKbps
        self.sourceFolder = sourceFolder
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, artist, title, fileType, duration, bitrateKbps, sourceFolder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        artist = try container.decode(String.self, forKey: .artist)
        title = try container.decode(String.self, forKey: .title)
        fileType = try container.decode(String.self, forKey: .fileType)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        bitrateKbps = try container.decodeIfPresent(Int.self, forKey: .bitrateKbps)
        sourceFolder = try container.decode(String.self, forKey: .sourceFolder)
    }
}

@MainActor
final class TrackIndexStore: ObservableObject {
    @Published private(set) var tracks: [LocalTrack] = []
    @Published private(set) var lastScannedAt: Date?
    private var matchingCatalog: MatchCatalog?

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
        matchingCatalog = nil
    }

    /// Clears an index whose approved source locations have changed. The next
    /// library check will perform a fresh read-only scan.
    func invalidate() throws {
        try LocalStorage.save(TrackIndexSnapshot(tracks: [], lastScannedAt: nil), named: "local-track-index.json")
        tracks = []
        lastScannedAt = nil
        matchingCatalog = nil
    }

    func cachedMatchingCatalog() -> MatchCatalog? { matchingCatalog }

    func cacheMatchingCatalog(_ catalog: MatchCatalog) { matchingCatalog = catalog }
}

private struct TrackIndexSnapshot: Codable {
    var tracks: [LocalTrack]
    var lastScannedAt: Date?
}
