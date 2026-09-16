import Foundation

struct SetlistEvent: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var date: Date?
    var requestSongs: [RequestedSong]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, date: Date? = nil, requestSongs: [RequestedSong] = [], createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.date = date
        self.requestSongs = requestSongs
        self.createdAt = createdAt
    }

    var crateName: String {
        guard let date else { return name }
        return "\(name) — \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

struct RequestedSong: Identifiable, Codable, Hashable {
    let id: UUID
    var artist: String
    var title: String
    var notes: String?

    init(id: UUID = UUID(), artist: String, title: String, notes: String? = nil) {
        self.id = id
        self.artist = artist
        self.title = title
        self.notes = notes
    }

    var displayName: String { artist.isEmpty ? title : "\(artist) — \(title)" }
}
