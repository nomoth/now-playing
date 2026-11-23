import Foundation
import os

class AppleScriptManager {
    private let logger = Logger(subsystem: "com.jf.nowplaying", category: "AppleScriptManager")

    // Debug logging function
    private func debugLog(_ message: String) {
        #if DEBUG
        print("[AppleScriptManager] \(message)")
        #else
        logger.debug("\(message)")
        #endif
    }

    private func errorLog(_ message: String) {
        #if DEBUG
        print("[AppleScriptManager ERROR] \(message)")
        #else
        logger.error("\(message)")
        #endif
    }

    // DECISION: scripts run one at a time on a serial background queue, not on the main thread.
    // NSAppleScript's docs ask for the main thread, where a hung Spotify would freeze the menu bar on every poll.
    private let scriptQueue = DispatchQueue(label: "com.jf.nowplaying.applescript", qos: .utility)

    /// True while a script runs, so a slow Spotify does not pile up polls. Main thread only.
    private var isRunning = false

    // Cache compiled script for performance
    private lazy var spotifyStateScript: NSAppleScript? = {
        return loadScript(named: "spotify_state")
    }()

    // MARK: - Public Interface

    /// Must be called on the main thread, and calls `completion` on the main thread.
    /// Does nothing, without calling `completion`, while the previous call is still running.
    func getSpotifyState(completion: @escaping (String) -> Void) {
        guard !isRunning else {
            debugLog("⏳ Previous script still running, skipping this poll")
            return
        }
        guard let script = spotifyStateScript else {
            errorLog("❌ Failed to load spotify_state script")
            completion("error")
            return
        }
        isRunning = true
        scriptQueue.async {
            let output = self.execute(script)
            DispatchQueue.main.async {
                self.isRunning = false
                completion(output)
            }
        }
    }

    // MARK: - Private Methods

    private func loadScript(named name: String) -> NSAppleScript? {
        // Try to load from app bundle first
        if let scriptPath = Bundle.main.path(forResource: name, ofType: "applescript"),
           let scriptContent = try? String(contentsOfFile: scriptPath, encoding: .utf8) {
            let script = NSAppleScript(source: scriptContent)
            if script != nil {
                debugLog("✅ Loaded script from bundle: \(name)")
                return script
            }
        }

        // Fallback: try to load from Scripts directory relative to executable
        let executablePath = Bundle.main.bundlePath
        let scriptsPath = URL(fileURLWithPath: executablePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts")
            .appendingPathComponent("\(name).applescript")


        if let scriptContent = try? String(contentsOf: scriptsPath, encoding: .utf8) {
            let script = NSAppleScript(source: scriptContent)
            if script != nil {
                debugLog("✅ Loaded script from Scripts directory: \(name)")
                return script
            }
        }

        errorLog("❌ Failed to load script: \(name)")
        return nil
    }

    /// Runs on `scriptQueue`. The script bounds its own wait for Spotify (`with timeout`).
    private func execute(_ script: NSAppleScript) -> String {
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            errorLog("❌ AppleScript execution error: \(error)")
            return "error"
        }
        return result.stringValue ?? "error"
    }
}
