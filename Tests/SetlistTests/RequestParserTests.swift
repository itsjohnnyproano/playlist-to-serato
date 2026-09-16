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
}
