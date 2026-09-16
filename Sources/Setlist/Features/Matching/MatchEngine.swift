import Foundation

struct TrackCandidate: Identifiable, Hashable, Sendable {
    let track: LocalTrack
    let confidence: Int
    let versionLabels: [String]

    var id: UUID { track.id }

    /// Lower is a safer default for an unqualified client request.
    fileprivate var defaultVersionRank: Int {
        let labels = Set(versionLabels)
        if labels.isEmpty { return 0 }
        if labels.isSubset(of: Set(["clean", "explicit"])) { return 1 }
        if labels.isSubset(of: Set(["clean", "explicit", "intro"])) { return 2 }
        if labels.isSubset(of: Set(["clean", "explicit", "extended"])) { return 3 }
        if labels.isDisjoint(with: MatchEngine.unsuitableAutoVersionTerms) { return 5 }
        return 10
    }
}

enum RequestMatchStatus: Equatable {
    case autoMatched
    case chosen
    case missing
}

enum MatchEngine {
    private static let versionTerms = ["clean", "explicit", "dirty", "remix", "edit", "intro", "extended", "live", "instrumental", "bootleg", "mashup", "flip", "rework", "acapella", "starter", "transition", "blend", "hype"]
    fileprivate static let unsuitableAutoVersionTerms: Set<String> = ["dirty", "remix", "edit", "intro", "extended", "live", "instrumental", "bootleg", "mashup", "flip", "rework", "acapella", "starter", "transition", "blend", "hype"]
    private static let ignoredTokens: Set<String> = ["a", "an", "and", "the", "feat", "featuring", "ft", "with"]

    static func candidates(for request: RequestedSong, in tracks: [LocalTrack], limit: Int? = nil) -> [TrackCandidate] {
        MatchCatalog(tracks: tracks).candidates(for: request, limit: limit)
    }

    fileprivate static func candidate(for request: RequestedSong, document: MatchCatalog.Document) -> TrackCandidate? {
        let requestArtist = tokens(request.artist)
        let requestTitle = tokens(request.title)
        let rawRequest = tokens(request.rawText ?? request.displayName)
        let directScore = requestArtist.isEmpty ? 0 : structuredIdentity(title: requestTitle, artist: requestArtist, document: document)
        // Clients commonly paste "Title — Artist". Score that orientation too,
        // rather than allowing unordered filename tokens to decide the result.
        let reversedScore = requestArtist.isEmpty ? 0 : structuredIdentity(title: requestArtist, artist: requestTitle, document: document)
        let flexibleScore = rawIdentity(rawRequest, document: document)
        let identityScore = max(directScore, reversedScore, flexibleScore)
        let score = max(0, identityScore - versionPenalty(request: request, candidate: document.track))
        guard score >= 0.55 else { return nil }
        return TrackCandidate(track: document.track, confidence: Int((score * 100).rounded()), versionLabels: document.versionLabels)
    }

    static func status(for request: RequestedSong, event: SetlistEvent, candidates: [TrackCandidate]) -> RequestMatchStatus {
        let requestKey = request.id.uuidString
        if event.autoMatchedRequestIDs.contains(requestKey) { return .autoMatched }
        if event.selectedTrackPaths[requestKey] != nil { return .chosen }
        return .missing
    }

    /// The first release intentionally favors certainty over coverage. A client
    /// request only becomes an automatic choice when the artist/title identity
    /// is strong and the local file is an unqualified original version.
    static func automaticSelection(from candidates: [TrackCandidate]) -> TrackCandidate? {
        candidates.first {
            $0.confidence >= 92 && isSafeDefaultVersion($0)
        }
    }

    private static func isSafeDefaultVersion(_ candidate: TrackCandidate) -> Bool {
        // A clean tag still describes the original recording and is a useful,
        // DJ-safe fallback when the unqualified original is not in the library.
        candidate.defaultVersionRank <= 1
    }

    fileprivate static func versionLabels(for track: LocalTrack) -> [String] {
        // Folder names such as "New Remixes" must not turn every contained
        // record into a remix. Only evaluate the track metadata and filename.
        let source = "\(track.title) \(URL(fileURLWithPath: track.path).lastPathComponent)".lowercased()
        return versionTerms.filter { source.contains($0) }
    }

    private static func structuredIdentity(title: Set<String>, artist: Set<String>, document: MatchCatalog.Document) -> Double {
        guard !title.isEmpty else { return 0 }
        let titleScore = similarity(title, document.titleTokens)
        guard titleScore >= 0.7 else { return 0 }
        guard !artist.isEmpty else { return titleScore }
        let artistScore = artistSimilarity(artist, artistValue: document.track.artist)
        guard artistScore >= 0.45 else { return 0 }
        // Artist evidence prevents title collisions such as a different "Mi
        // Gente" or a cover of "Blinding Lights" becoming a 100% match.
        return (titleScore * 0.68) + (artistScore * 0.32)
    }

    private static func rawIdentity(_ rawRequest: Set<String>, document: MatchCatalog.Document) -> Double {
        guard !rawRequest.isEmpty else { return 0 }
        let titleScore = similarity(rawRequest, document.titleTokens)
        guard titleScore >= 0.7 else { return 0 }
        // Filename-only imports often place both artist and title in the title
        // field. They are useful candidates, but never deserve an automatic
        // match when the library has no artist metadata to corroborate them.
        guard !document.artistTokens.isEmpty else { return titleScore * 0.7 }
        let remainingRequestTokens = rawRequest
            .subtracting(document.titleTokens)
            .subtracting(Set(versionTerms))
        guard !remainingRequestTokens.isEmpty else { return titleScore }
        let artistScore = artistSimilarity(remainingRequestTokens, artistValue: document.track.artist)
        // If the raw input appears to include an artist, a title collision alone
        // is not a useful result. Keep it out of the version chooser entirely.
        guard artistScore >= 0.45 else { return 0 }
        return (titleScore * 0.75) + (artistScore * 0.25)
    }

    private static func artistSimilarity(_ left: Set<String>, artistValue: String) -> Double {
        let right = tokens(artistValue)
        let tokenScore = similarity(left, right)
        // Common pasted spelling such as "florida" needs to match the library's
        // "Flo Rida" without opening the door to unrelated artists.
        let compactLeft = left.sorted().joined()
        let compactRight = artistValue
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        if compactLeft == compactRight { return 1 }
        let shortest = min(compactLeft.count, compactRight.count)
        if shortest >= 5, (compactLeft.contains(compactRight) || compactRight.contains(compactLeft)) {
            return max(tokenScore, 0.9)
        }
        return tokenScore
    }

    fileprivate static func identityTitleTokens(for title: String) -> Set<String> {
        var base = title
            .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        if let dashRange = base.range(of: " - ", options: .backwards) {
            let suffix = String(base[dashRange.upperBound...]).lowercased()
            if versionTerms.contains(where: suffix.contains) {
                base = String(base[..<dashRange.lowerBound])
            }
        }
        return tokens(base)
    }

    private static func versionPenalty(request: RequestedSong, candidate: LocalTrack) -> Double {
        let requestedText = "\(request.artist) \(request.title)".lowercased()
        let requestedTerms = Set(versionTerms.filter { requestedText.contains($0) })
        let candidateTerms = Set(versionLabels(for: candidate))
        let unrequestedTerms = candidateTerms.subtracting(requestedTerms)

        return unrequestedTerms.reduce(0) { penalty, term in
            switch term {
            case "remix", "bootleg", "mashup", "flip", "rework", "live", "instrumental", "acapella", "starter", "transition", "blend": penalty + 0.25
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
            let titleTokens = MatchEngine.identityTitleTokens(for: track.title)
            let combinedTokens = artistTokens.union(titleTokens)
            let document = Document(track: track, artistTokens: artistTokens, titleTokens: titleTokens, combinedTokens: combinedTokens, versionLabels: MatchEngine.versionLabels(for: track))
            let index = documents.count
            documents.append(document)
            for token in combinedTokens { tokenIndex[token, default: []].append(index) }
        }
        self.documents = documents
        self.tokenIndex = tokenIndex
    }

    func candidates(for request: RequestedSong, limit: Int? = nil) -> [TrackCandidate] {
        let queryTokens = MatchEngine.tokens(request.rawText ?? request.displayName)
        let candidateIndices = Set(queryTokens.flatMap { tokenIndex[$0] ?? [] })
        let documentsToScore = candidateIndices.isEmpty ? documents : candidateIndices.map { documents[$0] }
        return documentsToScore.compactMap { MatchEngine.candidate(for: request, document: $0) }
            .sorted {
                if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
                if $0.defaultVersionRank != $1.defaultVersionRank { return $0.defaultVersionRank < $1.defaultVersionRank }
                return $0.track.title.localizedCaseInsensitiveCompare($1.track.title) == .orderedAscending
            }
            .prefix(limit ?? Int.max)
            .map { $0 }
    }
}
