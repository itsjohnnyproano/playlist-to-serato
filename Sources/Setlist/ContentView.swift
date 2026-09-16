import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var eventStore: EventStore
    @EnvironmentObject private var trackIndexStore: TrackIndexStore
    @State private var route: AppRoute = .newEvent

    private var selectedEvent: SetlistEvent? {
        guard case let .event(id) = route else { return nil }
        return eventStore.events.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(
                route: $route
            )
        } detail: {
            if case let .scanning(scanningEvent) = route {
                LibraryScanView(event: scanningEvent) {
                    route = .matching(scanningEvent.id)
                }
            } else if case let .matching(eventID) = route {
                MatchingView(eventID: eventID)
            } else if route == .musicLocations {
                MusicLocationsView()
            } else if route == .eventsHome {
                EventsHomeView { eventID in
                    route = .event(eventID)
                } onNewEvent: {
                    route = .newEvent
                }
            } else if route == .newEvent || selectedEvent == nil {
                ImportRequestView(event: nil) { savedEvent in
                    route = .event(savedEvent.id)
                } onCheckLibrary: { savedEvent in
                    route = trackIndexStore.tracks.isEmpty ? .scanning(savedEvent) : .matching(savedEvent.id)
                }
            } else if let selectedEvent {
                ImportRequestView(event: selectedEvent) { _ in } onCheckLibrary: { savedEvent in
                    route = trackIndexStore.tracks.isEmpty ? .scanning(savedEvent) : .matching(savedEvent.id)
                }
                    .id(selectedEvent.id)
            }
        }
        .tint(.setlistBlue)
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var eventStore: EventStore
    @Binding var route: AppRoute
    @State private var errorMessage: String?

    var body: some View {
        List(selection: selectedEventID) {
            Section("Library") {
                SidebarMenuRow(title: "Events", systemImage: "calendar") {
                    route = .eventsHome
                }
                SidebarMenuRow(title: "Missing songs", systemImage: "music.note.list", isAvailable: false) {}
                SidebarMenuRow(title: "Music locations", systemImage: "externaldrive") {
                    route = .musicLocations
                }
            }

            Section("Events") {
                ForEach(eventStore.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.name).fontWeight(.semibold)
                        Text(eventSummary(event))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(event.id)
                    .contextMenu {
                        Button("Delete event", role: .destructive) {
                            do {
                                try eventStore.delete(event)
                                if case let .event(selectedID) = route, selectedID == event.id {
                                    route = .eventsHome
                                }
                            } catch {
                                errorMessage = "Setlist could not delete this event."
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Setlist")
        .toolbar {
            Button {
                route = .newEvent
            } label: {
                Label("New event", systemImage: "plus")
            }
        }
        .alert("Setlist couldn’t save your change", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var selectedEventID: Binding<SetlistEvent.ID?> {
        Binding(
            get: {
                guard case let .event(id) = route else { return nil }
                return id
            },
            set: { id in
                route = id.map(AppRoute.event) ?? .eventsHome
            }
        )
    }

    private func eventSummary(_ event: SetlistEvent) -> String {
        let date = event.date?.formatted(.dateTime.month(.abbreviated).day()) ?? "No date"
        let requests = event.requestSongs.isEmpty ? "Draft" : "\(event.requestSongs.count) requests"
        return "\(date) · \(requests)"
    }
}

private struct EventsHomeView: View {
    @EnvironmentObject private var eventStore: EventStore
    let onSelectEvent: (SetlistEvent.ID) -> Void
    let onNewEvent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("EVENTS")
                    .font(.headline)
                    .foregroundStyle(Color.setlistBlue)
                Text("Every event, ready to prep.")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("Open an event to review its requests, match tracks, and build its crate.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if eventStore.events.isEmpty {
                ContentUnavailableView("No events yet", systemImage: "calendar.badge.plus", description: Text("Create your first event to bring in a client request."))
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(eventStore.events) { event in
                        Button { onSelectEvent(event.id) } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "calendar")
                                    .font(.title3)
                                    .foregroundStyle(Color.setlistBlue)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.name).fontWeight(.semibold)
                                    Text(eventHomeSummary(event))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(18)
                            .background(Color.primary.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button("New event", action: onNewEvent)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(48)
        .frame(maxWidth: 920, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func eventHomeSummary(_ event: SetlistEvent) -> String {
        let date = event.date?.formatted(.dateTime.month(.abbreviated).day()) ?? "No date"
        return "\(date) · \(event.requestSongs.count) request\(event.requestSongs.count == 1 ? "" : "s")"
    }
}

private struct SidebarMenuRow: View {
    let title: String
    let systemImage: String
    var isAvailable = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(isAvailable ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(isHovered ? Color.primary.opacity(0.08) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .onHover { isHovered = $0 }
    }
}

private struct MusicLocationsView: View {
    @EnvironmentObject private var musicLocationStore: MusicLocationStore
    @EnvironmentObject private var trackIndexStore: TrackIndexStore
    @State private var errorMessage: String?
    @State private var indexRefreshNeeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("LIBRARY SETUP")
                    .font(.headline)
                    .foregroundStyle(Color.setlistBlue)
                Text("Your music stays in your hands.")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("Choose only the folders or drives Setlist may scan. Nothing is scanned until you start a library check.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            GroupBox("Approved music locations") {
                if musicLocationStore.locations.isEmpty {
                    ContentUnavailableView(
                        "No locations approved",
                        systemImage: "folder.badge.plus",
                        description: Text("Add your main music folder or an external drive when you’re ready."))
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    VStack(spacing: 0) {
                        ForEach(musicLocationStore.locations) { location in
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(Color.setlistBlue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(location.displayName).fontWeight(.semibold)
                                    Text(location.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    do {
                                        try trackIndexStore.invalidate()
                                        try musicLocationStore.remove(location)
                                        indexRefreshNeeded = true
                                    } catch {
                                        errorMessage = "Setlist could not remove this approved location."
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 12)
                            if location.id != musicLocationStore.locations.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            HStack {
                Label("Setlist will never move, rename, edit, or delete a music file.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                if !trackIndexStore.tracks.isEmpty {
                    Button("Re-index library") {
                        do {
                            try trackIndexStore.invalidate()
                            indexRefreshNeeded = true
                            errorMessage = nil
                        } catch {
                            errorMessage = "Setlist could not prepare the library for a fresh index."
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Button("Add music folder…") { chooseFolder() }
                    .buttonStyle(.borderedProminent)
            }

            if indexRefreshNeeded {
                Label("Library re-index is ready. Open an event and choose “Check my library” to start the read-only scan.", systemImage: "arrow.clockwise.circle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.setlistBlue)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(48)
        .frame(maxWidth: 920, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a music folder"
        panel.message = "Setlist will only scan folders you approve."
        panel.prompt = "Approve folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try trackIndexStore.invalidate()
            try musicLocationStore.add(url: url)
            indexRefreshNeeded = true
            errorMessage = nil
        } catch {
            errorMessage = "Setlist could not save access to this folder: \(error.localizedDescription)"
        }
    }
}

private struct ImportRequestView: View {
    @EnvironmentObject private var eventStore: EventStore
    let existingEvent: SetlistEvent?
    let onSave: (SetlistEvent) -> Void
    let onCheckLibrary: (SetlistEvent) -> Void

    @State private var name = ""
    @State private var hasDate = false
    @State private var date = Date()
    @State private var source: RequestSource = .paste
    @State private var requestText = ""
    @State private var confirmation: String?
    @State private var errorMessage: String?

    init(
        event: SetlistEvent?,
        onSave: @escaping (SetlistEvent) -> Void,
        onCheckLibrary: @escaping (SetlistEvent) -> Void
    ) {
        existingEvent = event
        self.onSave = onSave
        self.onCheckLibrary = onCheckLibrary
        _name = State(initialValue: event?.name ?? "")
        _hasDate = State(initialValue: event?.date != nil)
        _date = State(initialValue: event?.date ?? .now)
        _requestText = State(initialValue: event?.requestSongs.map(\.displayName).joined(separator: "\n") ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(existingEvent == nil ? "NEW EVENT" : "EVENT REQUEST")
                        .font(.headline)
                        .foregroundStyle(Color.setlistBlue)
                    Text("Bring in the request.")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("Name the event, then import the request in whatever form your client sent it.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Event details") {
                    VStack(spacing: 14) {
                        TextField("Event name", text: $name)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Add event date", isOn: $hasDate)
                        if hasDate {
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Import source").font(.headline)
                    Picker("Import source", selection: $source) {
                        ForEach(RequestSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 48)
            .padding(.bottom, 24)
            .frame(maxWidth: 920, alignment: .leading)

            Divider()

            importBody
                .padding(.horizontal, 48)
                .padding(.vertical, 20)
                .frame(maxWidth: 920, maxHeight: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Read-only setup. Music files and existing Serato crates stay untouched.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button(existingEvent == nil ? "Save event" : "Save changes") {
                        save()
                    }
                    Button("Check my library") {
                        guard let event = save() else { return }
                        onCheckLibrary(event)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let confirmation {
                    Text(confirmation)
                        .foregroundStyle(.green)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 18)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var importBody: some View {
        switch source {
        case .paste:
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $requestText)
                    .font(.body)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)

                Text("One request per line. Use “Artist — Title” when possible; Setlist keeps the original text when it cannot confidently split it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
        case .spotify, .appleMusic, .spreadsheet:
            ContentUnavailableView(
                "Coming in a later build",
                systemImage: source.systemImage,
                description: Text("We’re beginning with pasted requests so the core local workflow is solid before adding external services and file formats."))
                .frame(maxWidth: .infinity, minHeight: 180)
        }
    }

    @discardableResult
    private func save() -> SetlistEvent? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let parsedSongs = source == .paste ? RequestParser.parse(requestText) : existingEvent?.requestSongs ?? []
        let songs = RequestParser.reconcile(parsedSongs, against: existingEvent?.requestSongs ?? [])
        let activeRequestIDs = Set(songs.map { $0.id.uuidString })
        let event = SetlistEvent(
            id: existingEvent?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            date: hasDate ? date : nil,
            requestSongs: songs,
            selectedTrackPaths: (existingEvent?.selectedTrackPaths ?? [:]).filter { activeRequestIDs.contains($0.key) },
            autoMatchedRequestIDs: (existingEvent?.autoMatchedRequestIDs ?? []).intersection(activeRequestIDs),
            createdAt: existingEvent?.createdAt ?? .now
        )
        do {
            try eventStore.save(event)
            errorMessage = nil
            confirmation = "Saved \(songs.count) request\(songs.count == 1 ? "" : "s")."
            onSave(event)
            return event
        } catch {
            confirmation = nil
            errorMessage = "Setlist could not save this event. Please try again."
            return nil
        }
    }
}

private struct LibraryScanView: View {
    @EnvironmentObject private var musicLocationStore: MusicLocationStore
    @EnvironmentObject private var trackIndexStore: TrackIndexStore
    let event: SetlistEvent
    let onDone: () -> Void

    @State private var update = ScanUpdate(phase: "Preparing scan", completed: 0, total: 0, currentFileName: nil)
    @State private var task: Task<Void, Never>?
    @State private var finished = false
    @State private var errorMessage: String?
    @State private var skippedPathCount = 0

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Text(event.name.uppercased())
                    .font(.headline)
                    .foregroundStyle(Color.setlistBlue)
                Text(finished ? "Your library is indexed." : "Looking through your library.")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(finished
                     ? "Setlist found \(trackIndexStore.tracks.count) local tracks. Nothing in your music or Serato library was changed."
                     : "Comparing the request against your approved music folders. This scan is read-only.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Image(systemName: finished ? "checkmark.circle.fill" : "music.note")
                .font(.system(size: 82))
                .foregroundStyle(finished ? .green : Color.setlistBlue)
                .symbolEffect(.pulse, options: .repeating, isActive: !finished)

            VStack(spacing: 12) {
                if update.total > 0 {
                    ProgressView(value: Double(update.completed), total: Double(update.total))
                        .frame(maxWidth: 620)
                } else {
                    ProgressView().controlSize(.regular)
                }
                HStack(spacing: 44) {
                    scanMetric(update.total > 0 ? "\(Int((Double(update.completed) / Double(update.total)) * 100))%" : "…", label: "complete")
                    scanMetric("\(update.completed)", label: "checked")
                    scanMetric(update.total > 0 ? "\(update.total)" : "…", label: "audio files")
                }
                Text(update.currentFileName ?? update.phase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            GroupBox {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Read-only scan").fontWeight(.semibold).foregroundStyle(.green)
                        Text("Serato folders, crates, backups, and music files are excluded from changes. Setlist only reads supported audio metadata.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }
            .frame(maxWidth: 620)

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if skippedPathCount > 0 {
                Text("\(skippedPathCount) location\(skippedPathCount == 1 ? " was" : "s were") skipped because Setlist could not read them. Reapprove or reconnect them, then refresh the library.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
            }

            HStack {
                if finished {
                    Button("Return to event", action: onDone)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Cancel scan") {
                        task?.cancel()
                        onDone()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { startScan() }
        .onDisappear { task?.cancel() }
    }

    private func scanMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title2.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 110)
    }

    private func startScan() {
        guard !musicLocationStore.locations.isEmpty else {
            errorMessage = "Add at least one Music location before scanning."
            return
        }
        task = Task {
            do {
                await trackIndexStore.loadSavedIndex()
                let result = try await LibraryScanner.scan(locations: musicLocationStore.locations, existingTracks: trackIndexStore.tracks) { scanUpdate in
                    await MainActor.run { update = scanUpdate }
                }
                guard !Task.isCancelled else { return }
                try await trackIndexStore.replace(with: result.tracks)
                skippedPathCount = result.skippedPaths.count
                finished = true
            } catch is CancellationError {
                // The user chose to cancel; do not replace a previous index.
            } catch {
                errorMessage = error.localizedDescription.isEmpty
                    ? "Setlist could not complete this scan. Your library was not changed."
                    : error.localizedDescription
            }
        }
    }
}

private enum RequestSource: CaseIterable, Identifiable {
    case paste, spotify, appleMusic, spreadsheet

    var id: Self { self }
    var title: String {
        switch self {
        case .paste: "Paste text"
        case .spotify: "Spotify playlist"
        case .appleMusic: "Apple Music"
        case .spreadsheet: "Spreadsheet / CSV"
        }
    }
    var systemImage: String {
        switch self {
        case .paste: "doc.on.clipboard"
        case .spotify: "music.note"
        case .appleMusic: "music.note"
        case .spreadsheet: "tablecells"
        }
    }
}
