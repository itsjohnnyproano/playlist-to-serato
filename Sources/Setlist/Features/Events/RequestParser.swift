import Foundation

enum RequestParser {
    static func parse(_ input: String) -> [RequestedSong] {
        input
            .split(whereSeparator: \.isNewline)
            .compactMap(parseLine)
    }

    static func parseLine(_ rawLine: Substring) -> RequestedSong? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        let separators = [" — ", " – ", " - "]
        for separator in separators where line.contains(separator) {
            let parts = line.components(separatedBy: separator)
            guard parts.count >= 2 else { continue }
            let artist = parts[0].trimmingCharacters(in: .whitespaces)
            let title = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespaces)
            guard !artist.isEmpty, !title.isEmpty else { return RequestedSong(artist: "", title: line, rawText: line) }
            return RequestedSong(artist: artist, title: title, rawText: line)
        }
        return RequestedSong(artist: "", title: line, rawText: line)
    }

    /// Retains stable request IDs for lines the DJ did not change. Selections
    /// are keyed by those IDs, so this prevents a name/date edit from silently
    /// discarding already-reviewed tracks.
    static func reconcile(_ parsedSongs: [RequestedSong], against existingSongs: [RequestedSong]) -> [RequestedSong] {
        var availableIDs = Dictionary(grouping: existingSongs, by: stableKey)
            .mapValues { $0.map(\.id) }

        return parsedSongs.map { song in
            let key = stableKey(song)
            guard var matchingIDs = availableIDs[key], let existingID = matchingIDs.first else { return song }
            matchingIDs.removeFirst()
            availableIDs[key] = matchingIDs
            return RequestedSong(id: existingID, artist: song.artist, title: song.title, notes: song.notes, rawText: song.rawText)
        }
    }

    private static func stableKey(_ song: RequestedSong) -> String {
        "\(normalized(song.artist))\u{1F}\(normalized(song.title))"
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }
}
