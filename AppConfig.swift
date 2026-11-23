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
    
    /// How long the position must stay still while Spotify reports "playing" to count as paused (in seconds)
    static let stalledPositionDelay: TimeInterval = 2.0

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

    // MARK: - Spectrum Analyzer (macOS 26+, replaces the playing symbol)

    /// UserDefaults key of the chosen SpectrumTheme
    static let spectrumThemeKey = "spectrumTheme"

    /// Number of bars
    static let spectrumBandCount = 18

    /// Frequency range shown, split into bands on a logarithmic scale (in Hz)
    static let spectrumMinFrequency: Float = 50
    static let spectrumMaxFrequency: Float = 16_000

    /// Band power shown as an empty bar and as a full bar (in dB relative to full scale)
    static let spectrumFloorDB: Float = -60
    static let spectrumCeilingDB: Float = -10

    /// Redraws per second while Spotify plays
    static let spectrumFrameRate: Double = 30

    /// How long the capture may bring only silence after it starts before the playing symbol stands in
    /// for the spectrum, as when audio capture is not allowed (in seconds)
    static let spectrumSilenceDelay: TimeInterval = 3

    /// Bars rise at once but fall at most this many full heights per second
    static let spectrumFallSpeed: Float = 2.5

    /// Peak marks stay up this long (in seconds), then fall this many full heights per second
    static let spectrumPeakHold: TimeInterval = 0.6
    static let spectrumPeakFallSpeed: Float = 0.6
}