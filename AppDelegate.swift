import Cocoa
import Foundation
import ServiceManagement
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var spotifyMonitor: SpotifyMonitor!
    private let logger = Logger(subsystem: "com.jf.nowplaying", category: "AppDelegate")
    
    // Thread-safe cache for formatted text to avoid repeated allocations
    private let cacheQueue = DispatchQueue(label: "com.jf.nowplaying.cache", attributes: .concurrent)
    private var _lastFormattedText: String = ""
    private var _lastInputHash: Int = 0
    
    // Debug logging function
    private func debugLog(_ message: String) {
        #if DEBUG
        print("[AppDelegate] \(message)")
        #else
        logger.debug("\(message)")
        #endif
    }
    
    private func errorLog(_ message: String) {
        #if DEBUG
        print("[AppDelegate ERROR] \(message)")
        #else
        logger.error("\(message)")
        #endif
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        debugLog("🚀 AppDelegate: applicationDidFinishLaunching called")
        setupMenuBarApp()
        setupStatusItem()
        setupSpotifyMonitor()
        debugLog("✅ AppDelegate: Setup complete")
    }
    
    private func setupMenuBarApp() {
        // Configure for menu bar only app
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupStatusItem() {
        debugLog("📱 Creating status item...")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        debugLog("📱 Status item created: \(self.statusItem != nil)")
        
        guard let button = statusItem.button else { 
            errorLog("❌ Failed to get status item button")
            return 
        }
        
        button.title = AppConfig.defaultSymbol
        button.imagePosition = .noImage
        debugLog("📱 Status item button configured")
        
        // Menu with options
        let menu = NSMenu()
        
        // Auto-start option
        let autoStartItem = NSMenuItem(title: "Start at Login", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartItem.state = isAutoStartEnabled() ? .on : .off
        menu.addItem(autoStartItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit NowPlaying", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    private func setupSpotifyMonitor() {
        spotifyMonitor = SpotifyMonitor()
        spotifyMonitor.delegate = self
        spotifyMonitor.startMonitoring()
        setupSpotifyAppMonitoring()
    }
    
    private func setupSpotifyAppMonitoring() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        
        // Detect Spotify launch
        notificationCenter.addObserver(
            self,
            selector: #selector(spotifyLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        
        // Detect Spotify termination
        notificationCenter.addObserver(
            self,
            selector: #selector(spotifyTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func spotifyLaunched(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == AppConfig.spotifyBundleID {
            debugLog("🚀 Spotify launched - resuming monitoring")
            // Small delay to let Spotify initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConfig.spotifyInitDelay) { [weak self] in
                self?.spotifyMonitor?.startMonitoring()
            }
        }
    }
    
    @objc private func spotifyTerminated(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == AppConfig.spotifyBundleID {
            debugLog("🚨 Spotify terminated - stopping monitoring")
            spotifyMonitor?.stopMonitoring()
            spotifyStateChanged(isPlaying: false, artist: nil, track: nil)
        }
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func toggleAutoStart() {
        if isAutoStartEnabled() {
            // Disable auto-start
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.unregister()
            } else {
                UserDefaults.standard.set(false, forKey: "autoStartEnabled")
                showManualInstructions(enable: false)
            }
        } else {
            // Enable auto-start
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.register()
            } else {
                UserDefaults.standard.set(true, forKey: "autoStartEnabled")
                showManualInstructions(enable: true)
            }
        }
        
        // Update the menu
        updateAutoStartMenuItem()
    }
    
    private func showManualInstructions(enable: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        
        if enable {
            alert.messageText = "Auto-start enabled"
            alert.informativeText = "To enable auto-start on your macOS version, add NowPlaying.app to System Preferences > Users & Groups > Login Items."
        } else {
            alert.messageText = "Auto-start disabled"
            alert.informativeText = "Don't forget to remove NowPlaying.app from login items in System Preferences."
        }
        
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func isAutoStartEnabled() -> Bool {        
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // For older versions, use UserDefaults as fallback
            return UserDefaults.standard.bool(forKey: "autoStartEnabled")
        }
    }
    
    private func updateAutoStartMenuItem() {
        if let menu = statusItem.menu,
           let autoStartItem = menu.item(at: 0) {
            autoStartItem.state = isAutoStartEnabled() ? .on : .off
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        spotifyMonitor?.stopMonitoring()
    }
}

extension AppDelegate: SpotifyMonitorDelegate {
    func spotifyStateChanged(isPlaying: Bool, artist: String?, track: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem.button else { return }
            
            if let artist = artist, let track = track, !artist.isEmpty, !track.isEmpty {
                // Limit length to avoid menu bar overflow
                let displayText = self.formatDisplayText(artist: artist, track: track)
                
                // Create text with integrated icon
                let icon = isPlaying ? AppConfig.playingSymbol : AppConfig.pausedSymbol
                button.title = "\(icon) \(displayText)"
                button.image = nil
                button.imagePosition = .noImage
            } else {
                button.title = AppConfig.defaultSymbol
                button.image = nil
                button.imagePosition = .noImage
            }
        }
    }
    
    func spotifyNotRunning() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem.button else { return }
            
            button.title = AppConfig.defaultSymbol
            button.image = nil
            button.imagePosition = .noImage
        }
    }
    
    func formatDisplayText(artist: String, track: String) -> String {
        // Create hash for cache key to avoid string comparison
        let inputHash = artist.hashValue &* 31 &+ track.hashValue
        
        // Thread-safe cache check
        let cachedResult = cacheQueue.sync {
            return _lastInputHash == inputHash ? _lastFormattedText : nil
        }
        
        if let cached = cachedResult {
            return cached
        }
        
        let maxLength = AppConfig.maxDisplayLength
        let result: String
        
        // Calculate total length upfront to avoid string interpolation
        let separatorLength = 3 // " - "
        let totalLength = artist.count + separatorLength + track.count
        
        if totalLength <= maxLength {
            // Use string builder for minimal allocations
            result = artist + " - " + track
        } else {
            // Optimized truncation with minimal string operations
            let ellipsisLength = 3 // "..."
            let availableLength = maxLength - separatorLength - ellipsisLength
            let artistLength = min(artist.count, availableLength / 2)
            let trackLength = availableLength - artistLength
            
            // Use substring operations instead of String() constructors
            let artistEnd = artist.index(artist.startIndex, offsetBy: artistLength)
            let trackEnd = track.index(track.startIndex, offsetBy: trackLength)
            
            result = String(artist[..<artistEnd]) + " - " + String(track[..<trackEnd]) + "..."
        }
        
        // Thread-safe cache update
        cacheQueue.async(flags: .barrier) {
            self._lastInputHash = inputHash
            self._lastFormattedText = result
        }
        
        return result
    }
}