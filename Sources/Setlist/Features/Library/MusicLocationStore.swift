import Foundation

struct MusicLocation: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var path: String
    var bookmarkData: Data
    var usesSecurityScope: Bool
    var addedAt: Date

    init(url: URL) throws {
        id = UUID()
        displayName = url.lastPathComponent
        path = url.path
        bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        usesSecurityScope = true
        addedAt = .now
    }
}

@MainActor
final class MusicLocationStore: ObservableObject {
    @Published private(set) var locations: [MusicLocation] = []

    init() {
        locations = (try? LocalStorage.load([MusicLocation].self, named: "music-locations.json")) ?? []
    }

    func add(url: URL) throws {
        let location = try MusicLocation(url: url)
        guard !locations.contains(where: { $0.path == location.path }) else { return }
        let updatedLocations = locations + [location]
        try LocalStorage.save(updatedLocations, named: "music-locations.json")
        locations = updatedLocations
    }

    func remove(_ location: MusicLocation) throws {
        let updatedLocations = locations.filter { $0.id != location.id }
        try LocalStorage.save(updatedLocations, named: "music-locations.json")
        locations = updatedLocations
    }
}
