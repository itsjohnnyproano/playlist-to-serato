import Foundation

struct TrackCandidate: Identifiable, Hashable, Sendable {
    let track: LocalTrack
    let confidence: Int
    let versionLabels: [String]

    var id: UUID { track.id }
}

enum RequestMatchStatus {
    case chosen
    case needsChoice
    case missing
}

enum MatchEngine {
    private static let versionTerms = ["clean", "explicit", "remix", "edit", "intro", "extended", "live", "instrumental", "bootleg", "mashup", "flip", "rework"]
    private static let ignoredTokens: Set<String> = ["a", "an", "and", "the", "feat", "featuring", "ft", "with"]

    static func candidates(for request: RequestedSong, in tracks: [LocalTrack], limit: Int = 5) -> [TrackCandidate] {
        MatchCatalog(tracks: tracks).candidates(for: request, limit: limit)
    }

    fileprivate static func candidate(for request: RequestedSong, document: MatchCatalog.Document) -> TrackCandidate? {
        let requestArtist = tokens(request.artist)
        let requestTitle = tokens(request.title)
        let rawRequest = tokens(request.rawText ?? request.displayName)
        let titleScore = similarity(requestTitle, document.titleTokens)
        let artistScore = requestArtist.isEmpty ? 1 : similarity(requestArtist, document.artistTokens)
        let structuredScore = requestArtist.isEmpty ? titleScore : (titleScore * 0.68) + (artistScore * 0.32)
        let flexibleScore = similarity(rawRequest, document.combinedTokens)
        let identityScore = max(structuredScore, flexibleScore)
        let score = max(0, identityScore - versionPenalty(request: request, candidate: document.track))
        guard score >= 0.35 else { return nil }
        return TrackCandidate(track: document.track, confidence: Int((score * 100).rounded()), versionLabels: document.versionLabels)
    }

    static func status(for request: RequestedSong, event: SetlistEvent, candidates: [TrackCandidate]) -> RequestMatchStatus {
        if event.selectedTrackPaths[request.id.uuidString] != nil { return .chosen }
        return candidates.first?.confidence ?? 0 >= 60 ? .needsChoice : .missing
    }

    fileprivate static func versionLabels(for track: LocalTrack) -> [String] {
        let source = "\(track.title) \(track.path)".lowercased()
        return versionTerms.filter { source.contains($0) }
    }

    private static func versionPenalty(request: RequestedSong, candidate: LocalTrack) -> Double {
        let requestedText = "\(request.artist) \(request.title)".lowercased()
        let requestedTerms = Set(versionTerms.filter { requestedText.contains($0) })
        let candidateTerms = Set(versionLabels(for: candidate))
        let unrequestedTerms = candidateTerms.subtracting(requestedTerms)

        return unrequestedTerms.reduce(0) { penalty, term in
            switch term {
            case "remix", "bootleg", "mashup", "flip", "rework", "live", "instrumental": penalty + 0.25
            default: penalty
            }
        }
    }

    fileprivate static func tokens(_ value: String) -> Set<String> {
        let normalized = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        return Set(normalized.split { !$0.isLetter && !$0.isNumber }.map(String.init))
            .subtracting(ignoredTokens)
    }

    private static func similarity(_ left: Set<String>, _ right: Set<String>) -> Double {
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left.isSubset(of: right) || right.isSubset(of: left) { return 1 }
        let overlap = Double(left.intersection(right).count)
        let union = Double(left.union(right).count)
        return overlap / union
    }
}

struct MatchCatalog: Sendable {
    struct Document: Sendable {
        let track: LocalTrack
        let artistTokens: Set<String>
        let titleTokens: Set<String>
        let combinedTokens: Set<String>
        let versionLabels: [String]
    }

    let documents: [Document]
    private let tokenIndex: [String: [Int]]

    init(tracks: [LocalTrack]) {
        var documents: [Document] = []
        var tokenIndex: [String: [Int]] = [:]
        documents.reserveCapacity(tracks.count)

        for track in tracks {
            let artistTokens = MatchEngine.tokens(track.artist)
            let titleTokens = MatchEngine.tokens(track.title)
            let combinedTokens = artistTokens.union(titleTokens)
            let document = Document(track: track, artistTokens: artistTokens, titleTokens: titleTokens, combinedTokens: combinedTokens, versionLabels: MatchEngine.versionLabels(for: track))
            let index = documents.count
            documents.append(document)
            for token in combinedTokens { tokenIndex[token, default: []].append(index) }
        }
        self.documents = documents
        self.tokenIndex = tokenIndex
    }

    func candidates(for request: RequestedSong, limit: Int = 5) -> [TrackCandidate] {
        let queryTokens = MatchEngine.tokens(request.rawText ?? request.displayName)
        let candidateIndices = Set(queryTokens.flatMap { tokenIndex[$0] ?? [] })
        let documentsToScore = candidateIndices.isEmpty ? documents : candidateIndices.map { documents[$0] }
        return documentsToScore.compactMap { MatchEngine.candidate(for: request, document: $0) }
            .sorted {
                $0.confidence == $1.confidence
                    ? $0.track.title.localizedCaseInsensitiveCompare($1.track.title) == .orderedAscending
                    : $0.confidence > $1.confidence
            }
            .prefix(limit)
            .map { $0 }
    }
}
