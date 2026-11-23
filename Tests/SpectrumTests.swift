import XCTest
@testable import NowPlaying

class SpectrumAnalyzerTests: XCTestCase {
    let sampleRate = 48_000.0

    private func sine(frequency: Double, amplitude: Double, count: Int) -> [Float] {
        (0..<count).map { Float(amplitude * sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    private func loudestBand(_ levels: [Float]) throws -> Int {
        try XCTUnwrap(levels.indices.max { levels[$0] < levels[$1] })
    }

    func testSilenceShowsEmptyBars() {
        let analyzer = SpectrumAnalyzer(sampleRate: sampleRate)
        let levels = analyzer.levels(of: [Float](repeating: 0, count: analyzer.fftSize))
        XCTAssertEqual(levels, [Float](repeating: 0, count: AppConfig.spectrumBandCount))
    }

    func testSineShowsInTheBandOfItsFrequencyOnly() throws {
        let analyzer = SpectrumAnalyzer(sampleRate: sampleRate, bandCount: 18, minFrequency: 50, maxFrequency: 16_000)
        let levels = analyzer.levels(of: sine(frequency: 1000, amplitude: 0.5, count: analyzer.fftSize))

        // Bands are log-spaced from 50 Hz with a ratio of 320 over 18 bands: 1 kHz falls in band 9
        XCTAssertEqual(try loudestBand(levels), 9)
        XCTAssertEqual(levels[9], 1)
        XCTAssertEqual(levels.first, 0)
        XCTAssertEqual(levels.last, 0)
    }

    func testLevelFollowsLoudnessInDecibels() throws {
        let analyzer = SpectrumAnalyzer(sampleRate: sampleRate)
        let amplitude = pow(10, -30.0 / 20) // -30 dBFS
        let levels = analyzer.levels(of: sine(frequency: 1000, amplitude: amplitude, count: analyzer.fftSize))

        // A Hann-windowed sine spreads 1.5x its power over its bins: +1.76 dB
        let expected = (-30 + 1.76 - AppConfig.spectrumFloorDB) / (AppConfig.spectrumCeilingDB - AppConfig.spectrumFloorDB)
        XCTAssertEqual(levels[try loudestBand(levels)], expected, accuracy: 0.02)
    }

    func testEveryBandHasBinsInIncreasingOrder() throws {
        let bins = SpectrumAnalyzer.bandBins(bandCount: 18, minFrequency: 50, maxFrequency: 16_000,
                                             binWidth: Float(sampleRate) / 4096, binCount: 2048)
        XCTAssertEqual(bins.count, 18)
        XCTAssertTrue(bins.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(zip(bins, bins.dropFirst()).allSatisfy { $0.lowerBound <= $1.lowerBound })
        XCTAssertLessThanOrEqual(try XCTUnwrap(bins.last).upperBound, 2048)
    }
}

class SpectrumMeterTests: XCTestCase {
    func testBarRisesAtOnceAndFallsAtFallSpeed() {
        var meter = SpectrumMeter(bandCount: 1)
        meter.update(levels: [0.8], at: 10)
        XCTAssertEqual(meter.bars[0], 0.8)

        meter.update(levels: [0], at: 10.1)
        XCTAssertEqual(meter.bars[0], 0.8 - AppConfig.spectrumFallSpeed * 0.1, accuracy: 1e-4)

        meter.update(levels: [0], at: 12)
        XCTAssertEqual(meter.bars[0], 0)
    }

    func testPeakHoldsThenFallsButNeverBelowTheBar() {
        let hold = AppConfig.spectrumPeakHold
        var meter = SpectrumMeter(bandCount: 1)
        meter.update(levels: [0.9], at: 0)

        meter.update(levels: [0.1], at: hold - 0.05)
        XCTAssertEqual(meter.peaks[0], 0.9, "the peak holds")

        meter.update(levels: [0.1], at: hold + 0.1)
        XCTAssertEqual(meter.peaks[0], 0.9 - AppConfig.spectrumPeakFallSpeed * 0.15, accuracy: 1e-4)

        meter.update(levels: [0.1], at: hold + 10)
        XCTAssertEqual(meter.peaks[0], 0.1)
    }
}

class SampleRingTests: XCTestCase {
    func testKeepsLatestSamplesOldestFirst() {
        var ring = SampleRing(capacity: 4)
        let input: [Float] = [1, 2, 3, 4, 5, 6]
        input.withUnsafeBufferPointer { ring.append($0) }

        var latest = [Float](repeating: 0, count: 3)
        ring.copyLatest(into: &latest)
        XCTAssertEqual(latest, [4, 5, 6])
    }

    func testKeepsFirstChannelOfInterleavedAudio() {
        var ring = SampleRing(capacity: 4)
        let stereo: [Float] = [1, -1, 2, -2, 3, -3]
        stereo.withUnsafeBufferPointer { ring.append($0, stride: 2) }

        var latest = [Float](repeating: 0, count: 3)
        ring.copyLatest(into: &latest)
        XCTAssertEqual(latest, [1, 2, 3])
    }
}
