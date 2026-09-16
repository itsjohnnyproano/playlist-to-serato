import Foundation

struct SetlistEvent: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var date: Date?
    var requestSongs: [RequestedSong]
    var selectedTrackPaths: [String: String]
    /// Request IDs selected automatically by the conservative match policy.
    /// Manual choices are deliberately kept separate so the review UI can
    /// explain which decisions still need the DJ's attention.
    var autoMatchedRequestIDs: Set<String>
    var createdAt: Date

    init(id: UUID = UUID(), name: String, date: Date? = nil, requestSongs: [RequestedSong] = [], selectedTrackPaths: [String: String] = [:], autoMatchedRequestIDs: Set<String> = [], createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.date = date
        self.requestSongs = requestSongs
        self.selectedTrackPaths = selectedTrackPaths
        self.autoMatchedRequestIDs = autoMatchedRequestIDs
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, date, requestSongs, selectedTrackPaths, autoMatchedRequestIDs, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        requestSongs = try container.decode([RequestedSong].self, forKey: .requestSongs)
        selectedTrackPaths = try container.decodeIfPresent([String: String].self, forKey: .selectedTrackPaths) ?? [:]
        autoMatchedRequestIDs = try container.decodeIfPresent(Set<String>.self, forKey: .autoMatchedRequestIDs) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    var crateName: String {
        guard let date else { return name }
        return "\(name) — \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

struct RequestedSong: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var artist: String
    var title: String
    var notes: String?
    var rawText: String?

    init(id: UUID = UUID(), artist: String, title: String, notes: String? = nil, rawText: String? = nil) {
        self.id = id
        self.artist = artist
        self.title = title
        self.notes = notes
        self.rawText = rawText
    }

    var displayName: String { artist.isEmpty ? title : "\(artist) — \(title)" }

    private enum CodingKeys: String, CodingKey {
        case id, artist, title, notes, rawText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        artist = try container.decode(String.self, forKey: .artist)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText)
    }
}
