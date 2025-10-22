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
    
    // Cache compiled script for performance
    private lazy var spotifyStateScript: NSAppleScript? = {
        return loadScript(named: "spotify_state")
    }()
    
    // MARK: - Public Interface
    
    func getSpotifyState(completion: @escaping (String) -> Void) {
        guard let script = spotifyStateScript else {
            errorLog("❌ Failed to load spotify_state script")
            completion("error")
            return
        }
        executeScript(script, completion: completion)
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
    
    private func executeScript(_ script: NSAppleScript, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let timeoutSeconds: TimeInterval = AppConfig.appleScriptTimeout
            var completed = false
            
            // Setup timeout task
            let timeoutTask = DispatchWorkItem {
                if !completed {
                    completed = true
                    self.errorLog("⏱️ AppleScript execution timeout after \(timeoutSeconds)s")
                    completion("timeout")
                }
            }
            
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutTask)
            
            // Execute script
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            
            // Cancel timeout if we completed in time
            timeoutTask.cancel()
            
            if !completed {
                completed = true
                
                if let error = error {
                    self.errorLog("❌ AppleScript execution error: \(error)")
                    completion("error")
                } else {
                    let resultString = result.stringValue ?? "error"
                    completion(resultString)
                }
            }
        }
    }
}