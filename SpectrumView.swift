import AppKit
import QuartzCore

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

/// Where each part of the meter goes. Shared by the themes, so that switching does not move
/// the title. Whole and half points stay sharp on Retina screens.
struct SpectrumLayout {
    static let barWidth: CGFloat = 1.5
    static let barGap: CGFloat = 0.5
    static let padding: CGFloat = 1.5
    static let peakGap: CGFloat = 0.5
    static let peakHeight: CGFloat = 1

    /// Part of the full height above which bars turn to the high color
    static let highFrom: CGFloat = 0.7

    struct Band {
        let low: CGRect
        let high: CGRect
        let peak: CGRect
    }

    let bandCount: Int
    let size: CGSize

    init(bandCount: Int, height: CGFloat) {
        self.bandCount = bandCount
        size = CGSize(width: 2 * Self.padding + CGFloat(bandCount) * (Self.barWidth + Self.barGap) - Self.barGap,
                      height: height)
    }

    /// Height of a full bar, leaving room for a peak mark above it
    var fullHeight: CGFloat {
        size.height - 2 * Self.padding - Self.peakGap - Self.peakHeight
    }

    /// `bar` and `peak` from 0 to 1
    func band(_ index: Int, bar: Float, peak: Float) -> Band {
        let x = Self.padding + CGFloat(index) * (Self.barWidth + Self.barGap)
        let bottom = Self.padding
        let barHeight = halfPoints(CGFloat(bar) * fullHeight)
        let highStart = halfPoints(Self.highFrom * fullHeight)
        return Band(
            low: CGRect(x: x, y: bottom, width: Self.barWidth, height: min(barHeight, highStart)),
            high: CGRect(x: x, y: bottom + highStart, width: Self.barWidth, height: max(barHeight - highStart, 0)),
            peak: CGRect(x: x, y: bottom + halfPoints(CGFloat(peak) * fullHeight) + Self.peakGap,
                         width: Self.barWidth, height: Self.peakHeight))
    }

    /// Rounds to the half point, a whole pixel on Retina screens
    private func halfPoints(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}

/// Shows the meter with Core Animation layers. A frame only moves a few layers: the status item
/// keeps its title and size, so neither it nor the menu bar is laid out or redrawn 30 times per second.
// DECISION: animate layers in a subview of the status item button, never `button.image` per frame.
// A new button image at 30 fps cost about 40% of a core (M2 Max), while drawing it took under 1%.
final class SpectrumView: NSView {
    private let layout: SpectrumLayout
    private let tile = CALayer()
    private var lowLayers: [CALayer] = []
    private var highLayers: [CALayer] = []
    private var peakLayers: [CALayer] = []

    var theme: SpectrumTheme = .winamp {
        didSet { applyColors() }
    }

    init(layout: SpectrumLayout) {
        self.layout = layout
        super.init(frame: CGRect(origin: .zero, size: layout.size))

        // Layer-hosting: the view shows these layers and never draws itself
        let root = CALayer()
        layer = root
        wantsLayer = true
        tile.frame = bounds
        tile.cornerRadius = 3
        root.addSublayer(tile)
        for _ in 0..<layout.bandCount {
            let low = CALayer(), high = CALayer(), peak = CALayer()
            [low, high, peak].forEach(root.addSublayer)
            lowLayers.append(low)
            highLayers.append(high)
            peakLayers.append(peak)
        }
        applyColors()
        let silence = [Float](repeating: 0, count: layout.bandCount)
        update(bars: silence, peaks: silence)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// Clicks go through to the status item button, which opens the menu.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    func update(bars: [Float], peaks: [Float]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true) // jump to each frame, no implicit animation
        for index in bars.indices {
            let band = layout.band(index, bar: bars[index], peak: peaks[index])
            lowLayers[index].frame = band.low
            highLayers[index].frame = band.high
            peakLayers[index].frame = band.peak
        }
        CATransaction.commit()
    }

    private func applyColors() {
        let tileColor: CGColor?
        let low: CGColor, high: CGColor, peak: CGColor
        switch theme {
        case .winamp:
            // Colors of the reference display, slightly brightened to read at menu bar size
            tileColor = CGColor(srgbRed: 0.03, green: 0.03, blue: 0.03, alpha: 1)
            low = CGColor(srgbRed: 0.35, green: 0.63, blue: 0.22, alpha: 1)
            high = CGColor(srgbRed: 0.84, green: 0.77, blue: 0.26, alpha: 1)
            peak = CGColor(srgbRed: 0.85, green: 0.83, blue: 0.81, alpha: 1)
        case .macOS:
            // The menu bar's text color: white on a dark menu bar, black on a light one
            let darkNames: [NSAppearance.Name] = [.darkAqua, .vibrantDark]
            let match = effectiveAppearance.bestMatch(from: [.aqua, .vibrantLight] + darkNames)
            let text = match.map(darkNames.contains) == true ? CGColor.white : CGColor.black
            tileColor = nil
            (low, high, peak) = (text, text, text)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tile.backgroundColor = tileColor
        lowLayers.forEach { $0.backgroundColor = low }
        highLayers.forEach { $0.backgroundColor = high }
        peakLayers.forEach { $0.backgroundColor = peak }
        CATransaction.commit()
    }
}
