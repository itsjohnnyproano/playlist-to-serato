import SwiftUI

struct MatchingView: View {
    @EnvironmentObject private var eventStore: EventStore
    @EnvironmentObject private var trackIndexStore: TrackIndexStore
    let eventID: SetlistEvent.ID
    @State private var selectedRequestID: RequestedSong.ID?
    @State private var candidates: [RequestedSong.ID: [TrackCandidate]] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var event: SetlistEvent? { eventStore.events.first { $0.id == eventID } }
    private var selectedRequest: RequestedSong? {
        guard let event else { return nil }
        return event.requestSongs.first { $0.id == selectedRequestID } ?? event.requestSongs.first
    }

    var body: some View {
        Group {
            if let event {
                HStack(spacing: 0) {
                    requestList(event)
                        .frame(width: 310)
                    Divider()
                    candidatePanel(event)
                }
            } else {
                ContentUnavailableView("Event not found", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .task { await buildMatches() }
    }

    private func requestList(_ event: SetlistEvent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("REQUEST LIST").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text("\(event.requestSongs.count) songs · \(chosenCount(event)) selected")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(20)

            List(selection: $selectedRequestID) {
                ForEach(event.requestSongs) { request in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(request.displayName).lineLimit(1)
                        statusLabel(status(for: request, event: event))
                    }
                    .padding(.vertical, 5)
                    .tag(request.id)
                }
            }
            .listStyle(.inset)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder private func candidatePanel(_ event: SetlistEvent) -> some View {
        if isLoading {
            VStack(spacing: 14) {
                ProgressView()
                Text("Matching requests to your saved library index…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let request = selectedRequest {
            let matches = candidates[request.id] ?? []
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("CHOOSE TRACK VERSIONS").font(.headline).foregroundStyle(Color.setlistBlue)
                        Text(event.selectedTrackPaths[request.id.uuidString] == nil ? "Possible matches." : "Setlist finds. You choose.")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                        Text(event.selectedTrackPaths[request.id.uuidString] == nil
                             ? "These are suggestions only. This request remains Missing until you choose a version."
                             : "Original or standard clean versions are selected automatically only when the match is highly confident.")
                            .font(.title3).foregroundStyle(.secondary)
                    }

                    if matches.isEmpty {
                        ContentUnavailableView("Not in your library", systemImage: "magnifyingglass", description: Text("No local version reached Setlist’s confidence threshold. Keep it in Missing songs or search manually later."))
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(matches) { candidate in
                                candidateRow(candidate, request: request, event: event)
                                if candidate.id != matches.last?.id { Divider() }
                            }
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if event.selectedTrackPaths[request.id.uuidString] != nil {
                        Button("Clear selected version") {
                            do {
                                try eventStore.clearTrackSelection(eventID: event.id, requestID: request.id)
                                errorMessage = nil
                            } catch { errorMessage = "Setlist could not clear this track choice." }
                        }
                        .buttonStyle(.bordered)
                    }

                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                    Text("Choices save locally. Nothing is added to Serato until final crate creation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(SetlistTheme.contentPadding)
                .frame(maxWidth: SetlistTheme.contentWidth, alignment: .leading)
            }
        } else {
            ContentUnavailableView("No requests yet", systemImage: "music.note.list")
        }
    }

    private func candidateRow(_ candidate: TrackCandidate, request: RequestedSong, event: SetlistEvent) -> some View {
        let isChosen = event.selectedTrackPaths[request.id.uuidString] == candidate.track.path
        return Button {
            guard !isChosen else { return }
            do {
                try eventStore.selectTrack(eventID: event.id, requestID: request.id, trackPath: candidate.track.path)
                errorMessage = nil
            } catch { errorMessage = "Setlist could not save this track choice." }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isChosen ? "checkmark.circle.inset.filled" : "circle")
                    .font(.title2).foregroundStyle(isChosen ? Color.setlistBlue : Color.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.track.artist.isEmpty ? candidate.track.title : "\(candidate.track.artist) — \(candidate.track.title)")
                        .fontWeight(.semibold)
                    Text("\(qualityText(candidate.track)) · \(durationText(candidate.track.duration)) · \(candidate.track.sourceFolder)")
                        .font(.caption).foregroundStyle(.secondary)
                    if !candidate.versionLabels.isEmpty {
                        Text(candidate.versionLabels.map { $0.capitalized }.joined(separator: " · "))
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(candidate.confidence)%")
                    .font(.headline).foregroundStyle(candidate.confidence >= 90 ? .green : .orange)
            }
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isChosen ? Color.setlistBlue.opacity(0.10) : .clear)
    }

    private func status(for request: RequestedSong, event: SetlistEvent) -> RequestMatchStatus {
        MatchEngine.status(for: request, event: event, candidates: candidates[request.id] ?? [])
    }

    @ViewBuilder private func statusLabel(_ status: RequestMatchStatus) -> some View {
        switch status {
        case .autoMatched: Text("✓ Auto-matched").foregroundStyle(.green)
        case .chosen: Text("✓ Version chosen").foregroundStyle(.green)
        case .missing: Text("Missing track").foregroundStyle(.orange)
        }
    }

    private func chosenCount(_ event: SetlistEvent) -> Int { event.selectedTrackPaths.count }
    private func durationText(_ duration: TimeInterval?) -> String {
        guard let duration else { return "Unknown duration" }
        return Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))
    }

    private func qualityText(_ track: LocalTrack) -> String {
        guard let bitrate = track.bitrateKbps else { return "\(track.fileType) · Quality unknown" }
        return "\(track.fileType) · ~\(bitrate) kbps"
    }

    private func buildMatches() async {
        guard let event else { return }
        selectedRequestID = selectedRequestID ?? event.requestSongs.first?.id
        let requests = event.requestSongs
        let tracks = trackIndexStore.tracks
        let catalog: MatchCatalog
        if let cachedCatalog = trackIndexStore.cachedMatchingCatalog() {
            catalog = cachedCatalog
        } else {
            catalog = await Task.detached(priority: .userInitiated) { MatchCatalog(tracks: tracks) }.value
            trackIndexStore.cacheMatchingCatalog(catalog)
        }
        candidates = await Task.detached(priority: .userInitiated) {
            Dictionary(uniqueKeysWithValues: requests.map { ($0.id, catalog.candidates(for: $0)) })
        }.value
        applyConservativeAutoMatches(for: event)
        isLoading = false
    }

    private func applyConservativeAutoMatches(for event: SetlistEvent) {
        for request in event.requestSongs {
            do {
                if let candidate = MatchEngine.automaticSelection(from: candidates[request.id] ?? []) {
                    try eventStore.autoSelectTrack(eventID: event.id, requestID: request.id, trackPath: candidate.track.path)
                } else {
                    // Only revise decisions the app made itself; never erase a
                    // track the DJ explicitly selected.
                    try eventStore.clearAutomaticSelection(eventID: event.id, requestID: request.id)
                }
            } catch {
                errorMessage = "Setlist could not save an automatic match."
            }
        }
    }
}
