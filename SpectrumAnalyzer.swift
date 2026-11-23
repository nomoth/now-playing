import Accelerate

/// Turns the latest audio samples into one level per frequency band, from 0 (silent) to 1 (loud).
/// Bands are spread on a logarithmic scale, like the ear hears them.
final class SpectrumAnalyzer {
    /// Number of samples analyzed at once (a power of 2)
    let fftSize: Int

    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let bandBins: [Range<Int>]

    // Buffers reused on every call
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var power: [Float]

    init(sampleRate: Double,
         fftSize: Int = 4096,
         bandCount: Int = AppConfig.spectrumBandCount,
         minFrequency: Float = AppConfig.spectrumMinFrequency,
         maxFrequency: Float = AppConfig.spectrumMaxFrequency) {
        let log2Size = vDSP_Length(log2(Double(fftSize)))
        precondition(1 << log2Size == fftSize, "fftSize must be a power of 2")
        guard let fft = vDSP.FFT(log2n: log2Size, radix: .radix2, ofType: DSPSplitComplex.self) else {
            preconditionFailure("vDSP cannot set up a \(fftSize)-point FFT")
        }
        self.fftSize = fftSize
        self.fft = fft
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
        windowed = [Float](repeating: 0, count: fftSize)
        real = [Float](repeating: 0, count: fftSize / 2)
        imaginary = [Float](repeating: 0, count: fftSize / 2)
        power = [Float](repeating: 0, count: fftSize / 2)
        bandBins = Self.bandBins(bandCount: bandCount,
                                 minFrequency: minFrequency,
                                 maxFrequency: maxFrequency,
                                 binWidth: Float(sampleRate) / Float(fftSize),
                                 binCount: fftSize / 2)
    }

    /// FFT bins of each band. Every band gets at least one bin, so the lowest bands
    /// can share theirs when they are narrower than a bin.
    static func bandBins(bandCount: Int, minFrequency: Float, maxFrequency: Float, binWidth: Float, binCount: Int) -> [Range<Int>] {
        let ratio = maxFrequency / minFrequency
        return (0..<bandCount).map { band in
            let low = minFrequency * pow(ratio, Float(band) / Float(bandCount))
            let high = minFrequency * pow(ratio, Float(band + 1) / Float(bandCount))
            let first = min(Int((low / binWidth).rounded()), binCount - 1)
            let end = min(max(first + 1, Int((high / binWidth).rounded())), binCount)
            return first..<end
        }
    }

    /// Level of each band, from 0 to 1, for `fftSize` mono samples between -1 and 1.
    func levels(of samples: [Float]) -> [Float] {
        precondition(samples.count == fftSize, "expected \(fftSize) samples, got \(samples.count)")
        vDSP.multiply(samples, window, result: &windowed)

        let half = fftSize / 2
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                guard let realBase = realBuffer.baseAddress, let imaginaryBase = imaginaryBuffer.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imaginaryBase)
                windowed.withUnsafeBytes { bytes in
                    let complex = bytes.bindMemory(to: DSPComplex.self)
                    if let complexBase = complex.baseAddress {
                        vDSP_ctoz(complexBase, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fft.forward(input: split, output: &split)
                power.withUnsafeMutableBufferPointer { powerBuffer in
                    if let powerBase = powerBuffer.baseAddress {
                        vDSP_zvmags(&split, 1, powerBase, 1, vDSP_Length(half))
                    }
                }
            }
        }

        // vDSP's real FFT returns twice the DFT, and the Hann window halves a sine's peak:
        // a sine of amplitude A peaks at A * fftSize / 2, so its squared amplitude is power * 4 / fftSize².
        let scale = 4 / Float(fftSize * fftSize)
        let floor = AppConfig.spectrumFloorDB
        let range = AppConfig.spectrumCeilingDB - floor
        return bandBins.map { bins in
            // Summing the bins gives wide treble bands as much weight as narrow bass ones,
            // which keeps typical music (about as loud per octave) level across the bands.
            let bandPower = power[bins].reduce(0, +) * scale
            let decibels = 10 * log10(max(bandPower, 1e-12))
            return min(max((decibels - floor) / range, 0), 1)
        }
    }
}
