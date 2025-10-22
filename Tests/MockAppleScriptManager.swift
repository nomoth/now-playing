import Foundation
@testable import NowPlaying

class MockAppleScriptManager: AppleScriptManager {
    var mockResult: String = "playing|Test Artist|Test Track|0|180000"
    var getSpotifyStateCalled: Bool = false
    
    override func getSpotifyState(completion: @escaping (String) -> Void) {
        getSpotifyStateCalled = true
        completion(mockResult)
    }
    
    func reset() {
        getSpotifyStateCalled = false
        mockResult = "playing|Test Artist|Test Track|0|180000"
    }
}