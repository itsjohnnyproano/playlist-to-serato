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
