import XCTest
@testable import Setlist

final class RequestParserTests: XCTestCase {
    func testParsesArtistAndTitleWithEmDash() {
        let songs = RequestParser.parse("Beyoncé — CUFF IT")
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs[0].artist, "Beyoncé")
        XCTAssertEqual(songs[0].title, "CUFF IT")
    }

    func testKeepsUnstructuredLineAsTitle() {
        let songs = RequestParser.parse("September")
        XCTAssertEqual(songs[0].artist, "")
        XCTAssertEqual(songs[0].title, "September")
    }

    func testScannerSkipsSeratoDataFoldersCaseInsensitively() {
        XCTAssertTrue(LibraryScanner.isExcludedFolder(named: "_Serato_"))
        XCTAssertTrue(LibraryScanner.isExcludedFolder(named: "SERATO STUDIO"))
        XCTAssertFalse(LibraryScanner.isExcludedFolder(named: "Sounds for mixes"))
    }

    func testScannerRecognizesOnlySupportedAudioExtensions() {
        XCTAssertTrue(LibraryScanner.isSupportedAudioFile(URL(fileURLWithPath: "/tmp/test.MP3")))
        XCTAssertTrue(LibraryScanner.isSupportedAudioFile(URL(fileURLWithPath: "/tmp/test.flac")))
        XCTAssertFalse(LibraryScanner.isSupportedAudioFile(URL(fileURLWithPath: "/tmp/database V2")))
    }

    func testMatchEngineRanksMatchingArtistAndTitleFirst() {
        let request = RequestedSong(artist: "Beyoncé", title: "CUFF IT")
        let matchingTrack = LocalTrack(path: "/Music/Beyonce - Cuff It Clean.mp3", artist: "Beyonce", title: "CUFF IT (Clean)", fileType: "MP3", duration: 220, sourceFolder: "Music")
        let unrelatedTrack = LocalTrack(path: "/Music/Bruno Mars - 24K Magic.mp3", artist: "Bruno Mars", title: "24K Magic", fileType: "MP3", duration: 220, sourceFolder: "Music")

        let candidates = MatchEngine.candidates(for: request, in: [unrelatedTrack, matchingTrack])

        XCTAssertEqual(candidates.first?.track.path, matchingTrack.path)
        XCTAssertGreaterThan(candidates.first?.confidence ?? 0, 80)
    }

    func testMatchEngineDoesNotPenalizeUsefulDJVersionsButDemotesRemixes() {
        let request = RequestedSong(artist: "Doja Cat", title: "Paint The Town Red")
        let intro = LocalTrack(path: "/Music/Doja Cat - Paint The Town Red (Extended Intro).mp3", artist: "Doja Cat", title: "Paint The Town Red (Extended Intro)", fileType: "MP3", duration: 220, sourceFolder: "Music")
        let remix = LocalTrack(path: "/Music/Doja Cat - Paint The Town Red (Danny Dove Discotastic Remix).mp3", artist: "Doja Cat", title: "Paint The Town Red (Danny Dove Discotastic Remix)", fileType: "MP3", duration: 220, sourceFolder: "Music")

        let candidates = MatchEngine.candidates(for: request, in: [remix, intro])

        XCTAssertEqual(candidates.first?.track.path, intro.path)
        XCTAssertGreaterThan(candidates[0].confidence, candidates[1].confidence)
    }

    func testMatchEngineFindsArtistAndTitleInAnyPastedOrder() {
        let track = LocalTrack(path: "/Music/Karol G - Tusa.mp3", artist: "Karol G", title: "Tusa", fileType: "MP3", duration: 220, sourceFolder: "Music")
        let formats = ["Tusa - Karol G", "Tusa", "Tusa Karol G", "Karol G Tusa"]

        for format in formats {
            let request = RequestParser.parse(format)[0]
            let candidates = MatchEngine.candidates(for: request, in: [track])
            XCTAssertEqual(candidates.first?.track.path, track.path, "Expected a match for \(format)")
        }
    }

    func testAutoSelectionOnlyChoosesHighConfidenceOriginal() {
        let request = RequestedSong(artist: "50 Cent", title: "In Da Club")
        let original = LocalTrack(path: "/Music/50 Cent - In Da Club.mp3", artist: "50 Cent", title: "In Da Club", fileType: "MP3", duration: 220, sourceFolder: "Music")
        let remix = LocalTrack(path: "/Music/50 Cent - In Da Club (Club Remix).mp3", artist: "50 Cent", title: "In Da Club (Club Remix)", fileType: "MP3", duration: 220, sourceFolder: "Music")

        let candidates = MatchEngine.candidates(for: request, in: [remix, original])

        XCTAssertEqual(MatchEngine.automaticSelection(from: candidates)?.track.path, original.path)
    }

    func testQualifiedVersionStaysInReviewInsteadOfAutoSelecting() {
        let request = RequestedSong(artist: "50 Cent", title: "In Da Club")
        let cleanIntro = LocalTrack(path: "/Music/50 Cent - In Da Club (Clean Intro).mp3", artist: "50 Cent", title: "In Da Club (Clean Intro)", fileType: "MP3", duration: 220, sourceFolder: "Music")

        let candidates = MatchEngine.candidates(for: request, in: [cleanIntro])

        XCTAssertNil(MatchEngine.automaticSelection(from: candidates))
    }

    func testReversedTitleArtistRequestPrefersRealMetadataOverFilenameOnlyMatch() {
        let request = RequestParser.parse("Billie Jean — Michael Jackson")[0]
        let original = LocalTrack(path: "/Music/Michael Jackson - Billie Jean.mp3", artist: "Michael Jackson", title: "Billie Jean", fileType: "MP3", duration: 220, sourceFolder: "Music")
        let filenameOnly = LocalTrack(path: "/Music/1 michael jackson - billie jean.mp3", artist: "", title: "1 michael jackson - billie jean", fileType: "MP3", duration: 220, sourceFolder: "Music")

        let candidates = MatchEngine.candidates(for: request, in: [filenameOnly, original])

        XCTAssertEqual(candidates.first?.track.path, original.path)
        XCTAssertEqual(candidates.first?.confidence, 100)
        XCTAssertEqual(candidates.last?.confidence, 70)
    }

    func testRawArtistWordsRejectDifferentSongWithSameTitle() {
        let request = RequestParser.parse("mi gente j balvin")[0]
        let requestedRecording = LocalTrack(path: "/Music/J Balvin - Mi Gente.mp3", artist: "J Balvin & Willy William", title: "Mi Gente", fileType: "MP3", duration: 220, sourceFolder: "Music")
        let differentRecording = LocalTrack(path: "/Music/DJ Otto - Mi Gente.mp3", artist: "DJ Otto & Freebot", title: "Mi Gente", fileType: "MP3", duration: 220, sourceFolder: "Music")

        let candidates = MatchEngine.candidates(for: request, in: [differentRecording, requestedRecording])

        XCTAssertEqual(candidates.map(\.track.path), [requestedRecording.path])
        XCTAssertEqual(candidates.first?.confidence, 100)
    }

    func testCleanOriginalCanAutoSelectButAcapellaCannot() {
        let request = RequestedSong(artist: "N.O.R.E.", title: "Oye Mi Canto")
        let cleanOriginal = LocalTrack(path: "/Music/NORE - Oye Mi Canto (Clean).mp3", artist: "N.O.R.E.", title: "Oye Mi Canto (Clean)", fileType: "MP3", duration: 220, sourceFolder: "Music")
        let acapella = LocalTrack(path: "/Music/NORE - Oye Mi Canto Acapella.mp3", artist: "N.O.R.E.", title: "Oye Mi Canto Acapella", fileType: "MP3", duration: 220, sourceFolder: "Music")

        XCTAssertEqual(MatchEngine.automaticSelection(from: MatchEngine.candidates(for: request, in: [acapella, cleanOriginal]))?.track.path, cleanOriginal.path)
        XCTAssertNil(MatchEngine.automaticSelection(from: MatchEngine.candidates(for: request, in: [acapella])))
    }

    func testDJVersionSuffixDoesNotHideTheUnderlyingSong() {
        let request = RequestParser.parse("tlc no scrubs")[0]
        let TLCVersion = LocalTrack(path: "/Music/TLC - No Scrubs (Intro Clean).mp3", artist: "TLC", title: "No Scrubs (Intro Clean)", fileType: "MP3", duration: 220, sourceFolder: "Music")
        let unrelatedCover = LocalTrack(path: "/Music/Dropout - No Scrubs.mp3", artist: "Dropout & Wendy Sarmiento", title: "No Scrubs", fileType: "MP3", duration: 220, sourceFolder: "Music")

        let candidates = MatchEngine.candidates(for: request, in: [unrelatedCover, TLCVersion])

        XCTAssertEqual(candidates.map(\.track.path), [TLCVersion.path])
    }

    func testJoinedArtistSpellingMatchesSeparatedLibraryArtist() {
        let request = RequestParser.parse("florida low")[0]
        let low = LocalTrack(path: "/Music/Flo Rida - Low.mp3", artist: "Flo Rida ft. T-Pain", title: "Low (DJcity Throwback Edit)", fileType: "MP3", duration: 220, sourceFolder: "Music")

        XCTAssertEqual(MatchEngine.candidates(for: request, in: [low]).first?.track.path, low.path)
    }

    func testDifferentArtistWithSharedTitleBecomesMissing() {
        let request = RequestParser.parse("teddy swims run crazy")[0]
        let unrelatedCrazy = LocalTrack(path: "/Music/Gnarls Barkley - Crazy.mp3", artist: "Gnarls Barkley", title: "Crazy", fileType: "MP3", duration: 220, sourceFolder: "Music")

        XCTAssertTrue(MatchEngine.candidates(for: request, in: [unrelatedCrazy]).isEmpty)
    }

    func testSuggestionsRemainMissingUntilTheDJSelectsOne() {
        let request = RequestedSong(artist: "TLC", title: "No Scrubs")
        let candidate = LocalTrack(path: "/Music/TLC - No Scrubs (Intro Clean).mp3", artist: "TLC", title: "No Scrubs (Intro Clean)", fileType: "MP3", duration: 220, sourceFolder: "Music")
        let event = SetlistEvent(name: "Test", requestSongs: [request])

        XCTAssertEqual(MatchEngine.status(for: request, event: event, candidates: MatchEngine.candidates(for: request, in: [candidate])), .missing)
    }

    func testCandidatesAreNotCappedAtFive() {
        let request = RequestedSong(artist: "TLC", title: "No Scrubs")
        let tracks = (1...6).map { number in
            LocalTrack(path: "/Music/TLC - No Scrubs \(number).mp3", artist: "TLC", title: "No Scrubs (Clean \(number))", fileType: "MP3", duration: 220, sourceFolder: "Music")
        }

        XCTAssertEqual(MatchEngine.candidates(for: request, in: tracks).count, 6)
    }
}
