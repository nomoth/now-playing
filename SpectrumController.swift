import AppKit
import os

/// Runs the spectrum while Spotify plays: captures its audio, analyzes it and hands over one image per frame.
@available(macOS 26.0, *)
final class SpectrumController {
    /// 4096 samples cover about 85 ms at 48 kHz, fine enough for the lowest bands
    private static let fftSize = 4096

    private let tap = SpotifyAudioTap(capacity: SpectrumController.fftSize)
    private var analyzer: SpectrumAnalyzer?
    private var meter = SpectrumMeter()
    private var samples = [Float](repeating: 0, count: SpectrumController.fftSize)
    private var timer: Timer?
    private var framesSinceReport = 0
    private let onFrame: (NSImage) -> Void
    private let logger = Logger(subsystem: "com.jf.nowplaying", category: "SpectrumController")

    /// `onFrame` runs on the main thread.
    init(onFrame: @escaping (NSImage) -> Void) {
        self.onFrame = onFrame
    }

    deinit {
        stop()
    }

    /// Applies from the next frame
    var theme: SpectrumTheme = .winamp

    var isRunning: Bool { timer != nil }

    func start() throws {
        guard !isRunning else { return }
        try tap.start()
        let format = tap.format
        debugLog("🎚️ Capturing Spotify: \(format.mSampleRate) Hz, \(format.mChannelsPerFrame) channel(s), \(format.mBitsPerChannel) bits, flags 0x\(String(format.mFormatFlags, radix: 16))")
        analyzer = SpectrumAnalyzer(sampleRate: tap.sampleRate, fftSize: Self.fftSize)
        framesSinceReport = 0
        meter = SpectrumMeter()

        // Common modes keep the animation running while the menu is open
        let timer = Timer(timeInterval: 1 / AppConfig.spectrumFrameRate, repeats: true) { [weak self] _ in
            self?.drawFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        drawFrame()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tap.stop()
    }

    private func drawFrame() {
        guard let analyzer = analyzer else { return }
        tap.copyLatest(into: &samples)
        meter.update(levels: analyzer.levels(of: samples), at: ProcessInfo.processInfo.systemUptime)
        onFrame(SpectrumRenderer.image(of: meter, height: NSStatusBar.system.thickness - 4, theme: theme))
        reportActivityEverySecond()
    }

    /// Tells apart no audio at all (callbacks: 0) from silence (peak: 0), e.g. when capture is not allowed.
    private func reportActivityEverySecond() {
        framesSinceReport += 1
        guard framesSinceReport >= Int(AppConfig.spectrumFrameRate) else { return }
        framesSinceReport = 0
        let activity = tap.takeActivity()
        debugLog("🎚️ Last second: \(activity.callbacks) audio callbacks, peak \(activity.peak)")
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[SpectrumController] \(message)")
        #else
        logger.debug("\(message)")
        #endif
    }
}
