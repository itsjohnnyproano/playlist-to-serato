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
    var fileSize: Int64?
    var modificationDate: Date?
    var modificationTimeNanoseconds: Int64?

    init(path: String, artist: String, title: String, fileType: String, duration: TimeInterval?, bitrateKbps: Int? = nil, sourceFolder: String, fileSize: Int64? = nil, modificationDate: Date? = nil, modificationTimeNanoseconds: Int64? = nil) {
        id = UUID()
        self.path = path
        self.artist = artist
        self.title = title
        self.fileType = fileType
        self.duration = duration
        self.bitrateKbps = bitrateKbps
        self.sourceFolder = sourceFolder
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.modificationTimeNanoseconds = modificationTimeNanoseconds
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, artist, title, fileType, duration, bitrateKbps, sourceFolder, fileSize, modificationDate, modificationTimeNanoseconds
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
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        modificationDate = try container.decodeIfPresent(Date.self, forKey: .modificationDate)
        modificationTimeNanoseconds = try container.decodeIfPresent(Int64.self, forKey: .modificationTimeNanoseconds)
    }
}

@MainActor
final class TrackIndexStore: ObservableObject {
    @Published private(set) var tracks: [LocalTrack] = []
    @Published private(set) var lastScannedAt: Date?
    private var matchingCatalog: MatchCatalog?
    private var matchingCatalogTask: Task<MatchCatalog, Never>?

    init() {
    }

    private var didLoadSavedIndex = false
    private var loadTask: Task<TrackIndexSnapshot?, Never>?

    func loadSavedIndex() async {
        guard !didLoadSavedIndex else { return }
        if loadTask == nil {
            loadTask = Task.detached(priority: .utility) {
                try? LocalStorage.load(TrackIndexSnapshot.self, named: "local-track-index.json")
            }
        }
        let saved = await loadTask!.value
        guard !didLoadSavedIndex else { return }
        tracks = saved?.tracks ?? []
        lastScannedAt = saved?.lastScannedAt
        didLoadSavedIndex = true
        loadTask = nil
        prewarmMatchingCatalog()
    }

    func replace(with tracks: [LocalTrack]) async throws {
        let scannedAt = Date.now
        let snapshot = TrackIndexSnapshot(tracks: tracks, lastScannedAt: scannedAt)
        try await Task.detached(priority: .utility) {
            try LocalStorage.save(snapshot, named: "local-track-index.json")
        }.value
        self.tracks = tracks
        lastScannedAt = scannedAt
        didLoadSavedIndex = true
        matchingCatalog = nil
        matchingCatalogTask?.cancel()
        matchingCatalogTask = nil
        prewarmMatchingCatalog()
    }

    /// Clears an index whose approved source locations have changed. The next
    /// library check will perform a fresh read-only scan.
    func invalidate() throws {
        try LocalStorage.save(TrackIndexSnapshot(tracks: [], lastScannedAt: nil), named: "local-track-index.json")
        tracks = []
        lastScannedAt = nil
        didLoadSavedIndex = true
        matchingCatalog = nil
        matchingCatalogTask?.cancel()
        matchingCatalogTask = nil
    }

    func matchingCatalog() async -> MatchCatalog {
        if let matchingCatalog { return matchingCatalog }
        if matchingCatalogTask == nil { prewarmMatchingCatalog() }
        let catalog = await matchingCatalogTask!.value
        matchingCatalog = catalog
        matchingCatalogTask = nil
        return catalog
    }

    private func prewarmMatchingCatalog() {
        guard !tracks.isEmpty else { return }
        let indexedTracks = tracks
        matchingCatalogTask = Task.detached(priority: .userInitiated) {
            MatchCatalog(tracks: indexedTracks)
        }
    }
}

private struct TrackIndexSnapshot: Codable, Sendable {
    var tracks: [LocalTrack]
    var lastScannedAt: Date?
}
