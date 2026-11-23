import AppKit

enum SpectrumTheme: String, CaseIterable {
    /// Green bars turning yellow near the top, light peak marks, on a black tile
    case winamp
    /// Bars and peak marks in the menu bar's text color, straight on the menu bar
    case macOS

    var title: String {
        switch self {
        case .winamp: return "Winamp"
        case .macOS: return "macOS"
        }
    }
}

/// Draws the meter as a small LED display: bars with peak marks floating above them.
enum SpectrumRenderer {
    // Geometry in points, shared by the themes so that switching does not move the title.
    // Whole and half points stay sharp on Retina screens.
    private static let barWidth: CGFloat = 1.5
    private static let barGap: CGFloat = 0.5
    private static let padding: CGFloat = 1.5
    private static let peakGap: CGFloat = 0.5
    private static let peakHeight: CGFloat = 1
    private static let cornerRadius: CGFloat = 3

    /// Part of the full height above which bars turn to the `high` color
    private static let highFrom: CGFloat = 0.7

    private struct Palette {
        let background: NSColor?
        let low: NSColor
        let high: NSColor
        let peak: NSColor
    }

    private static func palette(for theme: SpectrumTheme) -> Palette {
        switch theme {
        case .winamp:
            // Colors of the reference display, slightly brightened to read at menu bar size
            return Palette(background: NSColor(srgbRed: 0.03, green: 0.03, blue: 0.03, alpha: 1),
                           low: NSColor(srgbRed: 0.35, green: 0.63, blue: 0.22, alpha: 1),
                           high: NSColor(srgbRed: 0.84, green: 0.77, blue: 0.26, alpha: 1),
                           peak: NSColor(srgbRed: 0.85, green: 0.83, blue: 0.81, alpha: 1))
        case .macOS:
            // A template image: macOS keeps the alpha and paints it in the menu bar's text color
            return Palette(background: nil, low: .black, high: .black, peak: .black)
        }
    }

    static func image(of meter: SpectrumMeter, height: CGFloat, theme: SpectrumTheme) -> NSImage {
        let bars = meter.bars
        let peaks = meter.peaks
        let palette = palette(for: theme)
        let width = padding + CGFloat(bars.count) * (barWidth + barGap) - barGap + padding
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            draw(bars: bars, peaks: peaks, palette: palette, in: rect)
            return true
        }
        image.isTemplate = theme == .macOS
        return image
    }

    private static func draw(bars: [Float], peaks: [Float], palette: Palette, in rect: NSRect) {
        if let background = palette.background {
            background.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }

        // Leaves room for a peak mark above a full bar
        let barsBottom = padding
        let fullHeight = rect.height - 2 * padding - peakGap - peakHeight
        let highStart = halfPoints(highFrom * fullHeight)
        for band in bars.indices {
            let x = padding + CGFloat(band) * (barWidth + barGap)
            let barHeight = halfPoints(CGFloat(bars[band]) * fullHeight)

            palette.low.setFill()
            NSRect(x: x, y: barsBottom, width: barWidth, height: min(barHeight, highStart)).fill()
            if barHeight > highStart {
                palette.high.setFill()
                NSRect(x: x, y: barsBottom + highStart, width: barWidth, height: barHeight - highStart).fill()
            }

            let peakY = barsBottom + halfPoints(CGFloat(peaks[band]) * fullHeight) + peakGap
            palette.peak.setFill()
            NSRect(x: x, y: peakY, width: barWidth, height: peakHeight).fill()
        }
    }

    /// Rounds to the half point, a whole pixel on Retina screens
    private static func halfPoints(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}
