import XCTest
@testable import NowPlaying

class AppDelegateTests: XCTestCase {
    
    var appDelegate: AppDelegate!
    
    override func setUp() {
        super.setUp()
        appDelegate = AppDelegate()
    }
    
    override func tearDown() {
        appDelegate = nil
        super.tearDown()
    }
    
    // MARK: - formatDisplayText Tests
    
    func testFormatDisplayTextShort() {
        let result = appDelegate.formatDisplayText(artist: "Artist", track: "Track")
        XCTAssertEqual(result, "Artist - Track")
    }
    
    func testFormatDisplayTextExactLength() {
        // 50 characters exactly: "12345678901234567890 - 123456789012345678901234567"
        let artist = "12345678901234567890"  // 20 chars
        let track = "123456789012345678901234567"  // 27 chars  
        let result = appDelegate.formatDisplayText(artist: artist, track: track)
        XCTAssertEqual(result, "\(artist) - \(track)")
        XCTAssertEqual(result.count, 50) // 20 + 3 + 27 = 50
    }
    
    func testFormatDisplayTextTruncation() {
        let longArtist = "Very Long Artist Name That Exceeds Normal Length"
        let longTrack = "Very Long Track Title That Also Exceeds Normal Length"
        let result = appDelegate.formatDisplayText(artist: longArtist, track: longTrack)
        
        XCTAssertTrue(result.hasSuffix("..."))
        XCTAssertTrue(result.contains(" - "))
        // Should be around 50 chars (maxLength - 3 for "..." + 3 for " - ")
        XCTAssertLessThanOrEqual(result.count, 53) // Some tolerance for calculation
    }
    
    func testFormatDisplayTextLongArtistShortTrack() {
        let longArtist = "This is a very long artist name that should be truncated"
        let shortTrack = "Short"
        let result = appDelegate.formatDisplayText(artist: longArtist, track: shortTrack)
        
        XCTAssertTrue(result.hasSuffix("..."))
        XCTAssertTrue(result.contains(" - "))
        XCTAssertTrue(result.contains("Short"))
    }
    
    func testFormatDisplayTextShortArtistLongTrack() {
        let shortArtist = "Short"
        let longTrack = "This is a very long track title that should be truncated"
        let result = appDelegate.formatDisplayText(artist: shortArtist, track: longTrack)
        
        XCTAssertTrue(result.hasSuffix("..."))
        XCTAssertTrue(result.contains(" - "))
        XCTAssertTrue(result.contains("Short"))
    }
    
    func testFormatDisplayTextEmptyStrings() {
        let result = appDelegate.formatDisplayText(artist: "", track: "")
        XCTAssertEqual(result, " - ")
    }
    
    func testFormatDisplayTextUnicodeCharacters() {
        let artist = "Artïst 🎵"
        let track = "Tråck ♫"
        let result = appDelegate.formatDisplayText(artist: artist, track: track)
        XCTAssertEqual(result, "Artïst 🎵 - Tråck ♫")
    }
    
    func testFormatDisplayTextSpecialCharacters() {
        let artist = "Art&st"
        let track = "Tr@ck"
        let result = appDelegate.formatDisplayText(artist: artist, track: track)
        XCTAssertEqual(result, "Art&st - Tr@ck")
    }
}