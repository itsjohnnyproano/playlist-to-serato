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
        event.autoMatchedRequestIDs.remove(requestID.uuidString)
        try save(event)
    }

    func autoSelectTrack(eventID: SetlistEvent.ID, requestID: RequestedSong.ID, trackPath: String) throws {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        var event = events[index]
        let key = requestID.uuidString
        // Preserve a DJ's manual decision, but allow a prior automatic decision
        // to be replaced when the matching engine improves or the index changes.
        guard event.selectedTrackPaths[key] == nil || event.autoMatchedRequestIDs.contains(key) else { return }
        event.selectedTrackPaths[key] = trackPath
        event.autoMatchedRequestIDs.insert(key)
        try save(event)
    }

    func clearAutomaticSelection(eventID: SetlistEvent.ID, requestID: RequestedSong.ID) throws {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        var event = events[index]
        let key = requestID.uuidString
        guard event.autoMatchedRequestIDs.contains(key) else { return }
        event.selectedTrackPaths.removeValue(forKey: key)
        event.autoMatchedRequestIDs.remove(key)
        try save(event)
    }

    func clearTrackSelection(eventID: SetlistEvent.ID, requestID: RequestedSong.ID) throws {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        var event = events[index]
        event.selectedTrackPaths.removeValue(forKey: requestID.uuidString)
        event.autoMatchedRequestIDs.remove(requestID.uuidString)
        try save(event)
    }

    /// Applies every automatic decision from one matching pass in a single
    /// atomic disk write. Manual DJ selections always remain untouched.
    func reconcileAutomaticSelections(eventID: SetlistEvent.ID, requestIDs: [RequestedSong.ID], selections: [String: String]) throws {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        var event = events[index]
        var changed = false

        for requestID in requestIDs {
            let key = requestID.uuidString
            guard event.selectedTrackPaths[key] == nil || event.autoMatchedRequestIDs.contains(key) else { continue }

            if let trackPath = selections[key] {
                if event.selectedTrackPaths[key] != trackPath || !event.autoMatchedRequestIDs.contains(key) {
                    event.selectedTrackPaths[key] = trackPath
                    event.autoMatchedRequestIDs.insert(key)
                    changed = true
                }
            } else if event.autoMatchedRequestIDs.contains(key) {
                event.selectedTrackPaths.removeValue(forKey: key)
                event.autoMatchedRequestIDs.remove(key)
                changed = true
            }
        }

        if changed { try save(event) }
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
