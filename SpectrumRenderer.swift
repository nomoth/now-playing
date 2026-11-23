import AppKit

/// Draws the meter as a small LED display: green bars turning yellow near the top,
/// and light peak marks floating above them.
enum SpectrumRenderer {
    // Geometry in points. Whole and half points stay sharp on Retina screens.
    private static let barWidth: CGFloat = 1.5
    private static let barGap: CGFloat = 0.5
    private static let padding: CGFloat = 1.5
    private static let peakGap: CGFloat = 0.5
    private static let peakHeight: CGFloat = 1
    private static let cornerRadius: CGFloat = 3

    /// Part of the full height above which bars turn yellow
    private static let yellowFrom: CGFloat = 0.7

    // Colors of the reference display, slightly brightened to read at menu bar size
    private static let backgroundColor = NSColor(srgbRed: 0.03, green: 0.03, blue: 0.03, alpha: 1)
    private static let greenColor = NSColor(srgbRed: 0.35, green: 0.63, blue: 0.22, alpha: 1)
    private static let yellowColor = NSColor(srgbRed: 0.84, green: 0.77, blue: 0.26, alpha: 1)
    private static let peakColor = NSColor(srgbRed: 0.85, green: 0.83, blue: 0.81, alpha: 1)

    static func image(of meter: SpectrumMeter, height: CGFloat) -> NSImage {
        let bars = meter.bars
        let peaks = meter.peaks
        let width = padding + CGFloat(bars.count) * (barWidth + barGap) - barGap + padding
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            draw(bars: bars, peaks: peaks, in: rect)
            return true
        }
    }

    private static func draw(bars: [Float], peaks: [Float], in rect: NSRect) {
        backgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

        // Leaves room for a peak mark above a full bar
        let barsBottom = padding
        let fullHeight = rect.height - 2 * padding - peakGap - peakHeight
        let yellowStart = halfPoints(yellowFrom * fullHeight)
        for band in bars.indices {
            let x = barLeft(band)
            let barHeight = halfPoints(CGFloat(bars[band]) * fullHeight)

            greenColor.setFill()
            NSRect(x: x, y: barsBottom, width: barWidth, height: min(barHeight, yellowStart)).fill()
            if barHeight > yellowStart {
                yellowColor.setFill()
                NSRect(x: x, y: barsBottom + yellowStart, width: barWidth, height: barHeight - yellowStart).fill()
            }

            let peakY = barsBottom + halfPoints(CGFloat(peaks[band]) * fullHeight) + peakGap
            peakColor.setFill()
            NSRect(x: x, y: peakY, width: barWidth, height: peakHeight).fill()
        }
    }

    private static func barLeft(_ band: Int) -> CGFloat {
        padding + CGFloat(band) * (barWidth + barGap)
    }

    /// Rounds to the half point, a whole pixel on Retina screens
    private static func halfPoints(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}
