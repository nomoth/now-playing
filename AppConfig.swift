import Foundation

/// Centralized configuration for NowPlaying app
struct AppConfig {
    // MARK: - Display Configuration
    
    /// Maximum length for menu bar text display
    static let maxDisplayLength = 50
    
    // MARK: - Timing Configuration
    
    /// Delay before checking Spotify state after launch
    static let spotifyInitDelay: TimeInterval = 2.0
    
    /// Polling interval when Spotify is playing (in seconds)
    static let playingPollingInterval: TimeInterval = 1.0
    
    /// Polling interval when Spotify is paused (in seconds)
    static let pausedPollingInterval: TimeInterval = 3.0
    
    /// Timeout for AppleScript execution (in seconds)
    static let appleScriptTimeout: TimeInterval = 3.0
    
    // MARK: - Bundle Configuration
    
    /// Spotify bundle identifier
    static let spotifyBundleID = "com.spotify.client"
    
    /// App bundle identifier
    static let appBundleID = "com.jf.nowplaying"
    
    // MARK: - Display Symbols
    
    /// Symbol displayed when music is playing
    static let playingSymbol = "♫"
    
    /// Symbol displayed when music is paused
    static let pausedSymbol = "❚❚"
    
    /// Default symbol when no music or app not available
    static let defaultSymbol = "♫"
}