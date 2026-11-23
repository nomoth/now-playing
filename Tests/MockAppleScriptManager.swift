import Foundation
@testable import NowPlaying

/// Builds an output of spotify_state.applescript from its fields
func scriptOutput(_ fields: String...) -> String {
    fields.joined(separator: SpotifyMonitor.fieldSeparator)
}

class MockAppleScriptManager: AppleScriptManager {
    var mockResult: String = scriptOutput("playing", "Test Artist", "Test Track", "0", "180000")
    var getSpotifyStateCalled: Bool = false
    
    override func getSpotifyState(completion: @escaping (String) -> Void) {
        getSpotifyStateCalled = true
        completion(mockResult)
    }
    
    func reset() {
        getSpotifyStateCalled = false
        mockResult = scriptOutput("playing", "Test Artist", "Test Track", "0", "180000")
    }
}