import Accelerate
import AppKit
import os

/// Whether the capture brings audio worth a spectrum. Only silence since the capture started, as when
/// audio capture is not allowed, means no audio once `delay` has passed, until the first sound; silence
/// after a sound does not count, so quiet passages keep the spectrum. A new start keeps the last answer:
/// after a capture that never heard anything, the next one waits for a sound before showing.
struct AudioPresence {
    let delay: TimeInterval
    private(set) var hasAudio = true
    private var startedAt: TimeInterval = 0
    private var heardSinceStart = false

    init(delay: TimeInterval = AppConfig.spectrumSilenceDelay) {
        self.delay = delay
    }

    mutating func start(at time: TimeInterval) {
        startedAt = time
        heardSinceStart = false
    }

    /// Takes whether the latest samples hold any sound. Returns true when `hasAudio` changed.
    mutating func update(heard: Bool, at time: TimeInterval) -> Bool {
        let hadAudio = hasAudio
        if heard {
            heardSinceStart = true
            hasAudio = true
        } else if !heardSinceStart && time - startedAt >= delay {
            hasAudio = false
        }
        return hasAudio != hadAudio
    }
}

/// Runs the spectrum while Spotify plays: captures its audio, analyzes it and moves the bars of `view`.
@available(macOS 26.0, *)
final class SpectrumController {
    /// 4096 samples cover about 85 ms at 48 kHz, fine enough for the lowest bands
    private static let fftSize = 4096

    /// To place in the status item button
    let view = SpectrumView(layout: SpectrumLayout(bandCount: AppConfig.spectrumBandCount,
                                                   height: NSStatusBar.system.thickness - 4))

    private let tap = SpotifyAudioTap(capacity: SpectrumController.fftSize)
    private var analyzer: SpectrumAnalyzer?
    private var meter = SpectrumMeter()
    private var samples = [Float](repeating: 0, count: SpectrumController.fftSize)
    private var timer: Timer?
    private var presence = AudioPresence()
    private var framesSinceReport = 0
    private let logger = Logger(subsystem: "com.jf.nowplaying", category: "SpectrumController")

    deinit {
        stop()
    }

    var theme: SpectrumTheme {
        get { view.theme }
        set { view.theme = newValue }
    }

    var isRunning: Bool { timer != nil }

    /// False while the capture brings only silence since it started (see `AudioPresence`): the spectrum
    /// keeps listening, but has nothing to show.
    var hasAudio: Bool { presence.hasAudio }

    /// Called on the main thread when `hasAudio` changes
    var onChange: (() -> Void)?

    func start() throws {
        guard !isRunning else { return }
        try tap.start()
        let format = tap.format
        debugLog("🎚️ Capturing Spotify: \(format.mSampleRate) Hz, \(format.mChannelsPerFrame) channel(s), \(format.mBitsPerChannel) bits, flags 0x\(String(format.mFormatFlags, radix: 16))")
        analyzer = SpectrumAnalyzer(sampleRate: tap.sampleRate, fftSize: Self.fftSize)
        framesSinceReport = 0
        meter = SpectrumMeter()
        presence.start(at: ProcessInfo.processInfo.systemUptime)

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
        let now = ProcessInfo.processInfo.systemUptime
        reportActivityEverySecond()
        if presence.update(heard: vDSP.maximumMagnitude(samples) > 0, at: now) {
            debugLog(presence.hasAudio ? "🎚️ Sound arrived, showing the spectrum" : "🎚️ Only silence so far, hiding the spectrum")
            // Later, so the owner never redraws from inside start()
            DispatchQueue.main.async { [weak self] in self?.onChange?() }
        }
        guard presence.hasAudio else { return }
        meter.update(levels: analyzer.levels(of: samples), at: now)
        view.update(bars: meter.bars, peaks: meter.peaks)
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
