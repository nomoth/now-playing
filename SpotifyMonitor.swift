import Foundation
import Cocoa
import os

protocol SpotifyMonitorDelegate: AnyObject {
    func spotifyStateChanged(isPlaying: Bool, artist: String?, track: String?)
    func spotifyNotRunning()
}

class SpotifyMonitor {
    /// Separates the fields of the script's output (ASCII unit separator, absent from artist and
    /// track names). Must match `fieldSeparator` in spotify_state.applescript.
    static let fieldSeparator = "\u{1F}"

    weak var delegate: SpotifyMonitorDelegate?
    private var isMonitoring = false
    private var pollingTimer: Timer?
    private var lastTrackInfo: (artist: String?, track: String?, isPlaying: Bool) = (nil, nil, false)
    /// Last position seen while Spotify reported "playing", nil after any other report
    private var lastPlayingPosition: Int?
    private var positionMovedAt = Date()
    private var currentPollingInterval: TimeInterval = AppConfig.playingPollingInterval
    private let logger = Logger(subsystem: "com.jf.nowplaying", category: "SpotifyMonitor")
    
    // AppleScript manager for handling all script operations
    private let scriptManager: AppleScriptManager
    
    init(scriptManager: AppleScriptManager = AppleScriptManager()) {
        self.scriptManager = scriptManager
    }
    
    // Debug logging function
    private func debugLog(_ message: String) {
        #if DEBUG
        print("[SpotifyMonitor] \(message)")
        #else
        logger.debug("\(message)")
        #endif
    }
    
    private func errorLog(_ message: String) {
        #if DEBUG
        print("[SpotifyMonitor ERROR] \(message)")
        #else
        logger.error("\(message)")
        #endif
    }
    
    func startMonitoring() {
        guard !isMonitoring else { 
            debugLog("⚠️ Already monitoring, skipping startMonitoring")
            return 
        }
        isMonitoring = true
        debugLog("🚀 SpotifyMonitor: Starting polling-based monitoring...")
        
        setupPollingTimer()
        
        // Check initial state
        updateSpotifyState()
        debugLog("✅ SpotifyMonitor: Polling monitoring started successfully")
    }
    
    func stopMonitoring() {
        isMonitoring = false
        pollingTimer?.invalidate()
        pollingTimer = nil

        // Forget the last track, so the first result after a restart is always shown
        // even when Spotify comes back on the same track in the same state
        lastTrackInfo = (nil, nil, false)
        lastPlayingPosition = nil
    }
    
    private func setupPollingTimer() {
        setupPollingTimer(interval: currentPollingInterval)
    }
    
    private func setupPollingTimer(interval: TimeInterval) {
        pollingTimer?.invalidate() // Cleanup existing timer
        currentPollingInterval = interval
        // No check that Spotify runs here: monitoring only runs while it does (see AppDelegate),
        // and the script answers "not_running" on its own if it quit in between.
        // Common modes keep polling while the menu is open, or the title would freeze next to a live spectrum.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateSpotifyState()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
        debugLog("⏰ Polling timer set up with \(interval)s interval")
    }
    
    private func handleSpotifyNotRunning() {
        if lastTrackInfo.artist != nil || lastTrackInfo.track != nil {
            lastTrackInfo = (nil, nil, false)
            delegate?.spotifyNotRunning()
        }
    }
    
    
    
    func updateSpotifyState() {
        // The completion runs on the main thread
        scriptManager.getSpotifyState { [weak self] result in
            // A result still in flight when monitoring stopped would show a track Spotify no longer plays
            guard let self, self.isMonitoring else { return }
            self.processResult(result)
        }
    }

    func processResult(_ result: String, now: Date = Date()) {
        if result == "not_running" || result == "error" {
            handleSpotifyNotRunning()
            return
        }
        if result == "timeout" {
            debugLog("⏱️ Spotify did not answer in time, keeping the current display")
            return
        }
        
        let components = result.components(separatedBy: Self.fieldSeparator)
        guard components.count >= 5 else { return }
        
        let reportedPlaying = components[0] == "playing"
        let artist = components[1].isEmpty ? nil : components[1]
        let track = components[2].isEmpty ? nil : components[2]
        let position = Int(components[3]) ?? 0 // in seconds
        let duration = Int(components[4]) ?? 0 // in milliseconds
        
        let isActuallyPlaying = detectPlaying(reportedPlaying: reportedPlaying, position: position, now: now)

        debugLog("🎵 Track info - position: \(position)s, duration: \(duration)ms, reported: \(reportedPlaying), actual: \(isActuallyPlaying)")
        
        // Only notify if something changed
        if lastTrackInfo.artist != artist || lastTrackInfo.track != track || lastTrackInfo.isPlaying != isActuallyPlaying {
            lastTrackInfo = (artist, track, isActuallyPlaying)
            delegate?.spotifyStateChanged(isPlaying: isActuallyPlaying, artist: artist, track: track)
            
            // Adjust polling interval based on playback state
            adjustPollingInterval(isPlaying: isActuallyPlaying)
        }
    }
    
    /// Spotify can report "playing" while the position stays still: that counts as paused once
    /// the position has not moved for `AppConfig.stalledPositionDelay`. Every other report is
    /// trusted as is, so play and pause show up on the next poll.
    private func detectPlaying(reportedPlaying: Bool, position: Int, now: Date) -> Bool {
        guard reportedPlaying else {
            lastPlayingPosition = nil
            return false
        }
        if position != lastPlayingPosition {
            lastPlayingPosition = position
            positionMovedAt = now
            return true
        }
        let stalled = now.timeIntervalSince(positionMovedAt) >= AppConfig.stalledPositionDelay
        if stalled {
            debugLog("🎵 Position unchanged (\(position)s) - detecting as PAUSED despite Spotify reporting 'playing'")
        }
        return !stalled
    }

    private func adjustPollingInterval(isPlaying: Bool) {
        let newInterval: TimeInterval = isPlaying ? AppConfig.playingPollingInterval : AppConfig.pausedPollingInterval
        
        // Only restart timer if interval changed
        if newInterval != currentPollingInterval {
            debugLog("🔄 Adjusting polling interval from \(currentPollingInterval)s to \(newInterval)s (\(isPlaying ? "playing" : "paused"))")
            setupPollingTimer(interval: newInterval)
        }
    }
    
}