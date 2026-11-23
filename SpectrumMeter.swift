import Foundation

/// What the menu bar shows of the band levels: bars that rise at once and fall smoothly,
/// and peak marks that stay a moment above them before falling.
struct SpectrumMeter {
    /// Heights from 0 to 1
    private(set) var bars: [Float]
    private(set) var peaks: [Float]

    private var peakRaisedAt: [TimeInterval]
    private var lastUpdate: TimeInterval?

    init(bandCount: Int = AppConfig.spectrumBandCount) {
        bars = [Float](repeating: 0, count: bandCount)
        peaks = bars
        peakRaisedAt = [TimeInterval](repeating: 0, count: bandCount)
    }

    /// `time` is any clock in seconds that only moves forward.
    mutating func update(levels: [Float], at time: TimeInterval) {
        precondition(levels.count == bars.count, "expected \(bars.count) levels, got \(levels.count)")
        let elapsed = Float(lastUpdate.map { time - $0 } ?? 0)
        lastUpdate = time

        for band in bars.indices {
            bars[band] = max(levels[band], bars[band] - AppConfig.spectrumFallSpeed * elapsed)
            if bars[band] >= peaks[band] {
                peaks[band] = bars[band]
                peakRaisedAt[band] = time
            } else if time - peakRaisedAt[band] >= AppConfig.spectrumPeakHold {
                peaks[band] = max(bars[band], peaks[band] - AppConfig.spectrumPeakFallSpeed * elapsed)
            }
        }
    }
}
