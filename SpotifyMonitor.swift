import Foundation
import Cocoa
import os

protocol SpotifyMonitorDelegate: AnyObject {
    func spotifyStateChanged(isPlaying: Bool, artist: String?, track: String?)
    func spotifyNotRunning()
}

class SpotifyMonitor {
    weak var delegate: SpotifyMonitorDelegate?
    private var isMonitoring = false
    private var pollingTimer: Timer?
    private var lastTrackInfo: (artist: String?, track: String?, isPlaying: Bool) = (nil, nil, false)
    private var lastPosition: Int = -1
    private var positionCheckTime: Date = Date()
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
        guard isMonitoring else { return }
        isMonitoring = false
        
        cleanupTimers()
    }
    
    func cleanupTimers() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    private func isSpotifyRunning() -> Bool {
        return NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == AppConfig.spotifyBundleID }
    }
    
    private func setupPollingTimer() {
        setupPollingTimer(interval: currentPollingInterval)
    }
    
    private func setupPollingTimer(interval: TimeInterval) {
        pollingTimer?.invalidate() // Cleanup existing timer
        currentPollingInterval = interval
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isSpotifyRunning() {
                self.updateSpotifyState()
            } else {
                self.handleSpotifyNotRunning()
            }
        }
        debugLog("⏰ Polling timer set up with \(interval)s interval")
    }
    
    private func handleSpotifyNotRunning() {
        if lastTrackInfo.artist != nil || lastTrackInfo.track != nil {
            lastTrackInfo = (nil, nil, false)
            delegate?.spotifyNotRunning()
        }
    }
    
    
    
    func updateSpotifyState() {
        scriptManager.getSpotifyState { [weak self] result in
            DispatchQueue.main.async {
                self?.processResult(result)
            }
        }
    }
    
    func processResult(_ result: String) {
        if result == "not_running" || result == "error" {
            handleSpotifyNotRunning()
            return
        }
        
        let components = result.components(separatedBy: "|")
        guard components.count >= 5 else { return }
        
        let reportedPlaying = components[0] == "playing"
        let artist = components[1].isEmpty ? nil : components[1]
        let track = components[2].isEmpty ? nil : components[2]
        let position = Int(components[3]) ?? 0 // in seconds
        let duration = Int(components[4]) ?? 0 // in milliseconds
        
        // Detect actual playing state by checking if position changed
        let now = Date()
        let timeDiff = now.timeIntervalSince(positionCheckTime)
        let isActuallyPlaying: Bool
        
        if timeDiff >= 2.0 { // Check position change over 2+ seconds
            if position == lastPosition && reportedPlaying {
                isActuallyPlaying = false // Position didn't change - probably paused
                debugLog("🎵 Position unchanged (\(position)s) - detecting as PAUSED despite Spotify reporting 'playing'")
            } else {
                isActuallyPlaying = reportedPlaying
            }
            lastPosition = position
            positionCheckTime = now
        } else {
            isActuallyPlaying = lastTrackInfo.isPlaying // Keep previous state until we have enough data
        }
        
        debugLog("🎵 Track info - position: \(position)s, duration: \(duration)ms, reported: \(reportedPlaying), actual: \(isActuallyPlaying)")
        
        // Only notify if something changed
        if lastTrackInfo.artist != artist || lastTrackInfo.track != track || lastTrackInfo.isPlaying != isActuallyPlaying {
            lastTrackInfo = (artist, track, isActuallyPlaying)
            delegate?.spotifyStateChanged(isPlaying: isActuallyPlaying, artist: artist, track: track)
            
            // Adjust polling interval based on playback state
            adjustPollingInterval(isPlaying: isActuallyPlaying)
        }
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