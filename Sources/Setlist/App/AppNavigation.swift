import Foundation

enum AppRoute: Equatable {
    case eventsHome
    case newEvent
    case musicLocations
    case event(SetlistEvent.ID)
    case scanning(SetlistEvent)
}
