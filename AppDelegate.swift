import Cocoa
import Foundation
import ServiceManagement
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let autoStartItem = NSMenuItem(title: "Start at Login", action: #selector(AppDelegate.toggleAutoStart),
                                           keyEquivalent: "")
    private var spotifyMonitor: SpotifyMonitor!
    /// The delayed start after Spotify launches. Cancelled if Spotify quits first, since nothing else
    /// would stop polling a Spotify that is gone.
    private var pendingMonitoringStart: DispatchWorkItem?
    /// What Spotify plays, nil when there is nothing to show
    private var spotifyState: (isPlaying: Bool, artist: String, track: String)?
    private let logger = Logger(subsystem: "com.jf.nowplaying", category: "AppDelegate")

    /// SpectrumController on macOS 26 and later. Typed AnyObject because a stored
    /// property cannot be limited to an OS version.
    private var spectrumController: AnyObject?

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
        observeMenuBarVisibility()
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
        button.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(placeSpectrumView),
                                               name: NSView.frameDidChangeNotification, object: button)
        debugLog("📱 Status item button configured")
        
        // Menu with options
        let menu = NSMenu()
        
        // Auto-start option, its checkmark set each time the menu opens
        menu.delegate = self
        menu.addItem(autoStartItem)

        // The spectrum only runs on macOS 26 and later
        if #available(macOS 26.0, *) {
            menu.addItem(spectrumThemeMenuItem())
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit NowPlaying", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    private func setupSpotifyMonitor() {
        spotifyMonitor = SpotifyMonitor()
        spotifyMonitor.delegate = self

        // Monitoring follows Spotify: the launch and quit notifications start and stop it, so it only
        // starts here if Spotify already runs. Observing first leaves no gap for a launch to slip through.
        setupSpotifyAppMonitoring()
        if !NSRunningApplication.runningApplications(withBundleIdentifier: AppConfig.spotifyBundleID).isEmpty {
            spotifyMonitor.startMonitoring()
        }
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
            pendingMonitoringStart?.cancel()
            let start = DispatchWorkItem { [weak self] in
                self?.pendingMonitoringStart = nil
                self?.spotifyMonitor?.startMonitoring()
            }
            pendingMonitoringStart = start
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConfig.spotifyInitDelay, execute: start)
        }
    }
    
    @objc private func spotifyTerminated(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == AppConfig.spotifyBundleID {
            debugLog("🚨 Spotify terminated - stopping monitoring")
            pendingMonitoringStart?.cancel()
            pendingMonitoringStart = nil
            spotifyMonitor?.stopMonitoring()
            spotifyNotRunning()
        }
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func toggleAutoStart() {
        if #available(macOS 13.0, *) {
            toggleLoginItem(SMAppService.mainApp)
        } else if isAutoStartEnabled() {
            UserDefaults.standard.set(false, forKey: "autoStartEnabled")
            showManualInstructions(enable: false)
        } else {
            UserDefaults.standard.set(true, forKey: "autoStartEnabled")
            showManualInstructions(enable: true)
        }
    }

    @available(macOS 13.0, *)
    private func toggleLoginItem(_ service: SMAppService) {
        var failure: Error?
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            errorLog("❌ Login item update failed: \(error)")
            failure = error
        }

        // macOS can hold a new login item until the user allows it, whether register() threw or not
        if service.status == .requiresApproval {
            let alert = NSAlert()
            alert.messageText = "Allow NowPlaying to start at login"
            alert.informativeText = "macOS needs your approval: turn NowPlaying on in System Settings > General > Login Items."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if showAlert(alert) == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        } else if let failure = failure {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't change Start at Login"
            alert.informativeText = failure.localizedDescription
            showAlert(alert)
        }
    }

    /// Brings this menu bar app to the front first: an inactive app's alert can open behind other windows.
    @discardableResult
    private func showAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        return alert.runModal()
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
        showAlert(alert)
    }
    
    private func isAutoStartEnabled() -> Bool {        
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // For older versions, use UserDefaults as fallback
            return UserDefaults.standard.bool(forKey: "autoStartEnabled")
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        spotifyMonitor?.stopMonitoring()
        stopSpectrum()
    }

    // MARK: - Display

    /// Shows `spotifyState` in the menu bar: while Spotify plays, the spectrum where it can run, otherwise a symbol.
    private func updateButton() {
        guard let button = statusItem.button else { return }
        guard let state = spotifyState else {
            stopSpectrum()
            showText(AppConfig.defaultSymbol, on: button)
            return
        }

        // Limit length to avoid menu bar overflow
        let displayText = formatDisplayText(artist: state.artist, track: state.track)
        if state.isPlaying && showSpectrum(title: " \(displayText)") {
            return
        }
        stopSpectrum()
        let icon = state.isPlaying ? AppConfig.playingSymbol : AppConfig.pausedSymbol
        showText("\(icon) \(displayText)", on: button)
    }

    private func showText(_ text: String, on button: NSStatusBarButton) {
        button.title = text
        button.image = nil
        button.imagePosition = .noImage
    }

    // MARK: - Menu bar visibility

    /// Why nobody can see the menu bar. The spectrum stops while there is any, rather than
    /// capture and draw for hours on a sleeping or locked Mac.
    private enum HiddenReason {
        case screensAsleep, screenLocked, sessionInactive
    }

    private var menuBarHiddenReasons: Set<HiddenReason> = []

    // Undocumented, but no documented notification tells when the screen locks
    private static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

    private func observeMenuBarVisibility() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(menuBarVisibilityChanged(_:)), name: name, object: nil)
        }
        for name in [Self.screenLockedNotification, Self.screenUnlockedNotification] {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(menuBarVisibilityChanged(_:)),
                                                                name: name, object: nil)
        }
    }

    @objc private func menuBarVisibilityChanged(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.screensDidSleepNotification: menuBarHiddenReasons.insert(.screensAsleep)
        case NSWorkspace.screensDidWakeNotification: menuBarHiddenReasons.remove(.screensAsleep)
        case Self.screenLockedNotification: menuBarHiddenReasons.insert(.screenLocked)
        case Self.screenUnlockedNotification: menuBarHiddenReasons.remove(.screenLocked)
        case NSWorkspace.sessionDidResignActiveNotification: menuBarHiddenReasons.insert(.sessionInactive)
        case NSWorkspace.sessionDidBecomeActiveNotification: menuBarHiddenReasons.remove(.sessionInactive)
        default: return
        }
        debugLog("🖥️ \(notification.name.rawValue), menu bar hidden by: \(menuBarHiddenReasons)")
        updateButton()
    }

    // MARK: - Spectrum

    private var spectrumTheme: SpectrumTheme {
        get {
            UserDefaults.standard.string(forKey: AppConfig.spectrumThemeKey).flatMap(SpectrumTheme.init(rawValue:)) ?? .winamp
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: AppConfig.spectrumThemeKey)
        }
    }

    private func spectrumThemeMenuItem() -> NSMenuItem {
        let themes = NSMenu()
        for theme in SpectrumTheme.allCases {
            let item = NSMenuItem(title: theme.title, action: #selector(selectSpectrumTheme(_:)), keyEquivalent: "")
            item.representedObject = theme.rawValue
            item.state = theme == spectrumTheme ? .on : .off
            themes.addItem(item)
        }
        let item = NSMenuItem(title: "Spectrum Style", action: nil, keyEquivalent: "")
        item.submenu = themes
        return item
    }

    @objc private func selectSpectrumTheme(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let theme = SpectrumTheme(rawValue: rawValue) else { return }
        spectrumTheme = theme
        for item in sender.menu?.items ?? [] {
            item.state = item === sender ? .on : .off
        }
        if #available(macOS 26.0, *), let controller = spectrumController as? SpectrumController {
            controller.theme = theme
        }
    }

    /// Shows the running spectrum in place of the playing symbol, before `title`. Returns false where
    /// it cannot run or while nobody can see the menu bar, so the caller falls back to the playing symbol.
    private func showSpectrum(title: String) -> Bool {
        guard #available(macOS 26.0, *), menuBarHiddenReasons.isEmpty, let button = statusItem.button else {
            return false
        }
        let controller: SpectrumController
        if let existing = spectrumController as? SpectrumController {
            controller = existing
        } else {
            controller = SpectrumController()
            spectrumController = controller
        }
        controller.theme = spectrumTheme
        do {
            try controller.start()
        } catch {
            errorLog("❌ Spectrum unavailable: \(error)")
            return false
        }

        // A blank image of the spectrum's size keeps its room before the title, and the view sits on it
        let size = controller.view.frame.size
        if button.image?.size != size {
            button.image = NSImage(size: size, flipped: false) { _ in true }
        }
        button.imagePosition = .imageLeft
        button.title = title
        if controller.view.superview !== button {
            button.addSubview(controller.view)
        }
        placeSpectrumView()
        return true
    }

    /// Keeps the spectrum view on the blank image, which moves when the button resizes to its title.
    @objc private func placeSpectrumView() {
        guard #available(macOS 26.0, *),
              let button = statusItem.button,
              let view = (spectrumController as? SpectrumController)?.view,
              view.superview === button,
              let imageRect = button.cell?.imageRect(forBounds: button.bounds) else { return }
        view.setFrameOrigin(imageRect.origin)
    }

    private func stopSpectrum() {
        if #available(macOS 26.0, *), let controller = spectrumController as? SpectrumController {
            controller.stop()
            controller.view.removeFromSuperview()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Reads the login item's state each time the menu opens, not only after a click: the user
    /// approves or removes it in System Settings, and a stale checkmark would make the next click
    /// do the opposite of what it shows.
    func menuNeedsUpdate(_ menu: NSMenu) {
        autoStartItem.state = isAutoStartEnabled() ? .on : .off
    }
}

extension AppDelegate: SpotifyMonitorDelegate {
    func spotifyStateChanged(isPlaying: Bool, artist: String?, track: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let artist = artist, let track = track, !artist.isEmpty, !track.isEmpty {
                self.spotifyState = (isPlaying, artist, track)
            } else {
                self.spotifyState = nil
            }
            self.updateButton()
        }
    }

    func spotifyNotRunning() {
        DispatchQueue.main.async { [weak self] in
            self?.spotifyState = nil
            self?.updateButton()
        }
    }
    
    func formatDisplayText(artist: String, track: String) -> String {
        let maxLength = AppConfig.maxDisplayLength
        let separatorLength = 3 // " - "

        guard artist.count + separatorLength + track.count > maxLength else {
            return artist + " - " + track
        }

        // Each side gets half of the room left by the separator; a side shorter than
        // its half leaves the rest to the other one.
        let availableLength = maxLength - separatorLength
        let half = availableLength / 2
        let artistLength = artist.count <= half ? artist.count : max(half, availableLength - track.count)
        return truncate(artist, to: artistLength) + " - " + truncate(track, to: availableLength - artistLength)
    }

    /// Returns `text` unchanged when it fits in `length` characters, otherwise its
    /// beginning followed by "...", `length` characters in total.
    private func truncate(_ text: String, to length: Int) -> String {
        guard text.count > length else { return text }
        let ellipsis = "..."
        return String(text.prefix(max(0, length - ellipsis.count))) + ellipsis
    }
}