import Foundation

enum MusicLocationError: LocalizedError {
    case accessSelection
    case createBookmark(underlying: Error)
    case saveLocations(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .accessSelection:
            "macOS did not grant temporary access to the folder selected in the picker."
        case let .createBookmark(underlying):
            "Could not create the folder permission bookmark. \(diagnostics(for: underlying))"
        case let .saveLocations(underlying):
            "Could not save Setlist's folder settings. \(diagnostics(for: underlying))"
        }
    }

    private func diagnostics(for error: Error) -> String {
        let nsError = error as NSError
        var details = ["[\(nsError.domain) \(nsError.code)]", nsError.localizedDescription]
        if let reason = nsError.localizedFailureReason, !reason.isEmpty {
            details.append(reason)
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append("Underlying: [\(underlying.domain) \(underlying.code)] \(underlying.localizedDescription)")
        }
        return details.joined(separator: " ")
    }
}

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
#if DEBUG
        // Local development uses the folder URL selected in the native picker.
        // Release builds always create a sandboxed, read-only security bookmark.
        bookmarkData = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        usesSecurityScope = false
#else
        // An NSOpenPanel result carries a temporary scope. Activate it while
        // serializing the durable, read-only bookmark; some macOS releases
        // otherwise refuse the bookmark with NSCocoaErrorDomain 256.
        guard url.startAccessingSecurityScopedResource() else {
            throw MusicLocationError.accessSelection
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            bookmarkData = try url.bookmarkData(
                // The app has a read-only user-selected-files entitlement. Marking the
                // bookmark the same way prevents macOS from attempting to create a
                // write-capable security scope.
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw MusicLocationError.createBookmark(underlying: error)
        }
        usesSecurityScope = true
#endif
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
        do {
            try LocalStorage.save(updatedLocations, named: "music-locations.json")
        } catch {
            throw MusicLocationError.saveLocations(underlying: error)
        }
        locations = updatedLocations
    }

    func remove(_ location: MusicLocation) throws {
        let updatedLocations = locations.filter { $0.id != location.id }
        try LocalStorage.save(updatedLocations, named: "music-locations.json")
        locations = updatedLocations
    }
}
