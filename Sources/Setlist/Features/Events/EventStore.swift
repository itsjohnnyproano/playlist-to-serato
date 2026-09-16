import Foundation

@MainActor
final class EventStore: ObservableObject {
    @Published private(set) var events: [SetlistEvent] = []

    init() {
        events = (try? LocalStorage.load([SetlistEvent].self, named: "events.json")) ?? []
    }

    func save(_ event: SetlistEvent) throws {
        var updatedEvents = events
        if let index = updatedEvents.firstIndex(where: { $0.id == event.id }) {
            updatedEvents[index] = event
        } else {
            updatedEvents.insert(event, at: 0)
        }
        try LocalStorage.save(updatedEvents, named: "events.json")
        events = updatedEvents
    }

    func delete(_ event: SetlistEvent) throws {
        let updatedEvents = events.filter { $0.id != event.id }
        try LocalStorage.save(updatedEvents, named: "events.json")
        events = updatedEvents
    }

    func selectTrack(eventID: SetlistEvent.ID, requestID: RequestedSong.ID, trackPath: String) throws {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        var event = events[index]
        event.selectedTrackPaths[requestID.uuidString] = trackPath
        try save(event)
    }

    func clearTrackSelection(eventID: SetlistEvent.ID, requestID: RequestedSong.ID) throws {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        var event = events[index]
        event.selectedTrackPaths.removeValue(forKey: requestID.uuidString)
        try save(event)
    }
}

extension JSONEncoder {
    static var setlist: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var setlist: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
