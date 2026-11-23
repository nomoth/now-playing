import CoreAudio
import Foundation
import os

/// The most recent audio samples, overwriting the oldest ones when full
struct SampleRing {
    private var storage: [Float]
    private var writeIndex = 0

    init(capacity: Int) {
        storage = [Float](repeating: 0, count: capacity)
    }

    /// Appends every `stride`-th sample, the first channel of interleaved audio.
    mutating func append(_ samples: UnsafeBufferPointer<Float>, stride: Int = 1) {
        var index = 0
        while index < samples.count {
            storage[writeIndex] = samples[index]
            writeIndex = (writeIndex + 1) % storage.count
            index += stride
        }
    }

    /// Fills `buffer` with the latest `buffer.count` samples, oldest first.
    func copyLatest(into buffer: inout [Float]) {
        precondition(buffer.count <= storage.count, "asked for more samples than the ring keeps")
        var readIndex = (writeIndex - buffer.count + storage.count) % storage.count
        for index in buffer.indices {
            buffer[index] = storage[readIndex]
            readIndex = (readIndex + 1) % storage.count
        }
    }

    mutating func clear() {
        storage = [Float](repeating: 0, count: storage.count)
        writeIndex = 0
    }
}

struct AudioTapError: Error, CustomStringConvertible {
    let step: String
    let status: OSStatus

    var description: String { "could not \(step) (OSStatus \(status))" }
}

/// Captures Spotify's audio output, mixed down to mono, through a Core Audio process tap.
/// macOS asks the user once for permission to capture other apps' audio; when it is denied,
/// the tap only delivers silence.
// DECISION: the spectrum requires macOS 26, which taps a process by bundle ID.
// macOS 14.2 taps need Spotify's Core Audio process object looked up first: not worth the code for older systems.
@available(macOS 26.0, *)
final class SpotifyAudioTap {
    private(set) var sampleRate: Double = 48_000

    private let ring: OSAllocatedUnfairLock<SampleRing>
    private let ioQueue = DispatchQueue(label: "com.jf.nowplaying.audiotap", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var tapUUID = UUID()
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    init(capacity: Int) {
        ring = OSAllocatedUnfairLock(initialState: SampleRing(capacity: capacity))
    }

    deinit {
        stop()
    }

    var isRunning: Bool { ioProcID != nil }

    func start() throws {
        guard !isRunning else { return }
        do {
            try createTap()
            try createAggregateDevice()
            try startIO()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let ioProcID = ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        ring.withLock { $0.clear() }
    }

    /// Fills `buffer` with the latest samples, oldest first.
    func copyLatest(into buffer: inout [Float]) {
        // Unchecked: the closure runs right away under the lock, so writing to `buffer` is safe
        ring.withLockUnchecked { $0.copyLatest(into: &buffer) }
    }

    // MARK: - Setup

    private func createTap() throws {
        let description = CATapDescription(monoMixdownOfProcesses: [])
        description.bundleIDs = [AppConfig.spotifyBundleID]
        description.name = "NowPlaying spectrum"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        tapUUID = description.uuid
        try check(AudioHardwareCreateProcessTap(description, &tapID), "create the Spotify audio tap")

        var format = AudioStreamBasicDescription()
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "read the tap format")
        sampleRate = format.mSampleRate
    }

    /// The tap only delivers audio through an aggregate device that includes it.
    private func createAggregateDevice() throws {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NowPlaying spectrum",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUUID.uuidString, kAudioSubTapDriftCompensationKey: true],
            ],
        ]
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID), "create the aggregate device")
    }

    private func startIO() throws {
        let ring = self.ring
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let buffer = buffers.first, let data = buffer.mData else { return }
            let channels = max(Int(buffer.mNumberChannels), 1)
            let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                              count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            ring.withLock { $0.append(samples, stride: channels) }
        }, "create the audio callback")
        try check(AudioDeviceStart(aggregateID, ioProcID), "start capturing")
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw AudioTapError(step: step, status: status) }
    }
}
