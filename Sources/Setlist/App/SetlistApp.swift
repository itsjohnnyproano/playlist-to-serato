import AppKit
import SwiftUI

@main
struct SetlistApp: App {
    @NSApplicationDelegateAdaptor(SetlistApplicationDelegate.self) private var applicationDelegate
    @StateObject private var eventStore = EventStore()
    @StateObject private var musicLocationStore = MusicLocationStore()
    @StateObject private var trackIndexStore = TrackIndexStore()
    @StateObject private var playback = PlaybackController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(eventStore)
                .environmentObject(musicLocationStore)
                .environmentObject(trackIndexStore)
                .environmentObject(playback)
                .frame(minWidth: 1_050, minHeight: 700)
                .task { await trackIndexStore.loadSavedIndex() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

final class SetlistApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
