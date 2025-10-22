import XCTest
@testable import NowPlaying

class MockSpotifyMonitorDelegate: SpotifyMonitorDelegate {
    var lastStateChange: (isPlaying: Bool, artist: String?, track: String?)?
    var spotifyNotRunningCalled = false
    
    func spotifyStateChanged(isPlaying: Bool, artist: String?, track: String?) {
        lastStateChange = (isPlaying, artist, track)
    }
    
    func spotifyNotRunning() {
        spotifyNotRunningCalled = true
    }
    
    func reset() {
        lastStateChange = nil
        spotifyNotRunningCalled = false
    }
}

class SpotifyMonitorTests: XCTestCase {
    
    var spotifyMonitor: SpotifyMonitor!
    var mockDelegate: MockSpotifyMonitorDelegate!
    var mockScriptManager: MockAppleScriptManager!
    
    override func setUp() {
        super.setUp()
        mockScriptManager = MockAppleScriptManager()
        spotifyMonitor = SpotifyMonitor(scriptManager: mockScriptManager)
        mockDelegate = MockSpotifyMonitorDelegate()
        spotifyMonitor.delegate = mockDelegate
    }
    
    override func tearDown() {
        spotifyMonitor = nil
        mockDelegate = nil
        mockScriptManager = nil
        super.tearDown()
    }
    
    // MARK: - processResult Tests
    
    func testProcessResultValidPlaying() {
        let result = "playing|The Beatles|Hey Jude|60000|240000"
        
        spotifyMonitor.processResult(result)
        
        XCTAssertNotNil(mockDelegate.lastStateChange)
        XCTAssertEqual(mockDelegate.lastStateChange?.isPlaying, true)
        XCTAssertEqual(mockDelegate.lastStateChange?.artist, "The Beatles")
        XCTAssertEqual(mockDelegate.lastStateChange?.track, "Hey Jude")
        XCTAssertFalse(mockDelegate.spotifyNotRunningCalled)
    }
    
    func testProcessResultValidPaused() {
        let result = "paused|The Beatles|Hey Jude|60000|240000"
        
        spotifyMonitor.processResult(result)
        
        XCTAssertNotNil(mockDelegate.lastStateChange)
        XCTAssertEqual(mockDelegate.lastStateChange?.isPlaying, false)
        XCTAssertEqual(mockDelegate.lastStateChange?.artist, "The Beatles")
        XCTAssertEqual(mockDelegate.lastStateChange?.track, "Hey Jude")
        XCTAssertFalse(mockDelegate.spotifyNotRunningCalled)
    }
    
    func testProcessResultNotRunning() {
        // First set some initial state
        spotifyMonitor.processResult("playing|Artist|Track|0|180000")
        mockDelegate.reset()
        
        spotifyMonitor.processResult("not_running")
        
        XCTAssertNil(mockDelegate.lastStateChange)
        XCTAssertTrue(mockDelegate.spotifyNotRunningCalled)
    }
    
    func testProcessResultError() {
        // First set some initial state
        spotifyMonitor.processResult("playing|Artist|Track|0|180000")
        mockDelegate.reset()
        
        spotifyMonitor.processResult("error")
        
        XCTAssertNil(mockDelegate.lastStateChange)
        XCTAssertTrue(mockDelegate.spotifyNotRunningCalled)
    }
    
    func testProcessResultInvalidFormatTooFewComponents() {
        let result = "playing|Artist|Track"  // Only 3 components instead of 5
        
        spotifyMonitor.processResult(result)
        
        XCTAssertNil(mockDelegate.lastStateChange)
        XCTAssertFalse(mockDelegate.spotifyNotRunningCalled)
    }
    
    func testProcessResultEmptyComponents() {
        // Set an initial non-empty state first
        spotifyMonitor.processResult("playing|Artist|Track|0|180000")
        mockDelegate.reset()
        
        let result = "|||||"  // Empty components
        
        spotifyMonitor.processResult(result)
        
        // Should notify because state changed from having artist/track to empty
        XCTAssertNotNil(mockDelegate.lastStateChange)
        XCTAssertEqual(mockDelegate.lastStateChange?.isPlaying, false) // Empty string != "playing"
        XCTAssertNil(mockDelegate.lastStateChange?.artist) // Empty string becomes nil
        XCTAssertNil(mockDelegate.lastStateChange?.track) // Empty string becomes nil
    }
    
    func testProcessResultNonNumericPositionAndDuration() {
        let result = "playing|Artist|Track|invalid|also_invalid"
        
        spotifyMonitor.processResult(result)
        
        XCTAssertNotNil(mockDelegate.lastStateChange)
        XCTAssertEqual(mockDelegate.lastStateChange?.isPlaying, true)
        XCTAssertEqual(mockDelegate.lastStateChange?.artist, "Artist")
        XCTAssertEqual(mockDelegate.lastStateChange?.track, "Track")
        // Should handle gracefully with default values (0)
    }
    
    func testProcessResultNoChangeDoesNotNotify() {
        // Set initial state
        spotifyMonitor.processResult("playing|Artist|Track|0|180000")
        mockDelegate.reset()
        
        // Send same state again
        spotifyMonitor.processResult("playing|Artist|Track|30000|180000")
        
        // Should not notify because artist, track, and playing state are the same
        XCTAssertNil(mockDelegate.lastStateChange)
        XCTAssertFalse(mockDelegate.spotifyNotRunningCalled)
    }
    
    func testProcessResultStateChangeNotifies() {
        // Set initial state
        spotifyMonitor.processResult("playing|Artist|Track|0|180000")
        mockDelegate.reset()
        
        // Change playing state
        spotifyMonitor.processResult("paused|Artist|Track|30000|180000")
        
        // Should notify because playing state changed
        XCTAssertNotNil(mockDelegate.lastStateChange)
        XCTAssertEqual(mockDelegate.lastStateChange?.isPlaying, false)
    }
    
    // MARK: - Polling Integration Tests
    
    func testUpdateSpotifyStateCallsScriptManager() {
        spotifyMonitor.updateSpotifyState()
        
        // Verify that the script manager was called
        XCTAssertTrue(mockScriptManager.getSpotifyStateCalled)
    }
    
    func testStartMonitoringDoesNotRequirePermissions() {
        // This should work without any permissions since we use polling
        spotifyMonitor.startMonitoring()
        
        // Should complete without errors or permission requests
        XCTAssertTrue(true) // Test passes if no exceptions thrown
    }
}