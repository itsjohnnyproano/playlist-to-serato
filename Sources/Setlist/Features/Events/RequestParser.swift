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
            guard !artist.isEmpty, !title.isEmpty else { return RequestedSong(artist: "", title: line) }
            return RequestedSong(artist: artist, title: title)
        }
        return RequestedSong(artist: "", title: line)
    }
}
