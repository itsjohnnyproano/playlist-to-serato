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
}
