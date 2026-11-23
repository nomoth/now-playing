# NowPlaying

A macOS menu bar app that shows the artist and track Spotify is playing.

## Features

- Artist and track in the menu bar, after ♫ while playing and ❚❚ while paused
- On macOS 26 and later, a spectrum analyzer of Spotify's audio in place of ♫ while playing
- Start at Login option
- Spotify is polled through AppleScript: every second while playing, every 3 seconds while paused

It only works with Spotify, and has no playback controls.

## Requirements

- macOS 11.0+, or macOS 26+ for the spectrum analyzer
- Spotify installed
- Xcode or the Command Line Tools, to build

## Installation

```bash
git clone https://github.com/nomoth/now-playing.git
cd now-playing
make run
```

### Keeping the Spotify permission across rebuilds

macOS ties the permission to control Spotify to the app's code signature. The app is signed ad hoc by default, and that signature changes with every build, so macOS may ask for the permission again after a rebuild. To avoid that, sign with a stable identity:

1. In Keychain Access, choose Keychain Access > Certificate Assistant > Create a Certificate…
2. Name it, for example `NowPlaying Dev`, with Identity Type *Self Signed Root* and Certificate Type *Code Signing*.
3. Build with it:

   ```bash
   make run SIGN_IDENTITY="NowPlaying Dev"
   ```

## Usage

1. Launch the app - appears as ♫ in menu bar
2. Grant Spotify automation permission when prompted
3. The menu bar shows the current artist and track

Click the menu bar item for the Start at Login, Spectrum Style (macOS 26+) and Quit options.

### Spectrum analyzer

On macOS 26 and later, the ♫ symbol becomes a spectrum analyzer while Spotify plays. It captures Spotify's audio through Core Audio (see [How the spectrum works](#how-the-spectrum-works)), so macOS asks once for permission to capture other apps' audio; nothing is recorded or stored. If the ♫ symbol stays while music plays, check that NowPlaying is allowed in System Settings > Privacy & Security > Screen & System Audio Recording: without that permission the capture only brings silence, and the symbol stands in for the spectrum.

The Spectrum Style menu switches between two looks: Winamp, green and yellow bars on a black tile, and macOS, bars in the menu bar's text color.

Band count, frequency range, sensitivity and motion are set in `AppConfig.swift`.

## How the spectrum works

The spectrum shows Spotify's output only: sounds from other apps do not move it.

### Capturing one app's audio

Core Audio process taps capture the audio an app sends to the output. `SpotifyAudioTap.swift` sets one up in four steps:

1. **Describe the tap**: `CATapDescription(monoMixdownOfProcesses: [])` with `bundleIDs = ["com.spotify.client"]`. Targeting a bundle ID is new in macOS 26. Taps exist since macOS 14.2, but there they take Core Audio process objects, which must first be looked up from the app's running process. The tap is private (`isPrivate`), so only NowPlaying sees it, and `muteBehavior = .unmuted`, so Spotify keeps playing through the speakers.
2. **Create it** with `AudioHardwareCreateProcessTap`, and read its sample rate from `kAudioTapPropertyFormat`.
3. **Wrap it in an aggregate device**: a tap delivers nothing on its own. It needs a private aggregate device that lists it under `kAudioAggregateDeviceTapListKey`, with `kAudioAggregateDeviceTapAutoStartKey` set.
4. **Read the samples** with an IO block on that aggregate device (`AudioDeviceCreateIOProcIDWithBlock` on a queue of its own, then `AudioDeviceStart`). The block copies the samples into a ring buffer behind an `OSAllocatedUnfairLock`, and the main thread reads the latest 4096 from it.

Notes:

- **Permission**: the app needs `NSAudioCaptureUsageDescription` in its Info.plist, and macOS asks once, on the first capture. A denied permission is not an error: the tap is created and runs, but delivers only silence. NowPlaying therefore treats 3 seconds of pure silence after a start as no audio, and shows ♫ until the first sound (`AudioPresence` in `SpectrumController.swift`). A change of the permission in System Settings applies once the app relaunches, and macOS offers to quit and reopen it.
- **Output changes**: the analyzer depends on the sample rate, which can change with the output device. NowPlaying listens to `kAudioHardwarePropertyDefaultOutputDevice` and to the tap's `kAudioTapPropertyFormat`, and rebuilds the tap, the aggregate device and the analyzer when either changes.
- **Lifetime**: the tap only exists while Spotify plays and someone can see the menu bar. It is destroyed on pause, when Spotify quits, and while the displays sleep or the screen is locked.

### From samples to bars

`SpectrumAnalyzer.swift` applies a Hann window and a 4096-point FFT with vDSP: 4096 samples last about 85 ms at 48 kHz, enough resolution for the lowest bands. It then sums the power of 18 bands spaced logarithmically from 50 Hz to 16 kHz, and maps each from -60 to -10 dBFS to a height between 0 and 1. `SpectrumMeter.swift` adds the motion: bars rise at once and fall smoothly, and peak marks hold for 0.6 s before falling.

### Drawing in the menu bar

A status item button shows a title and an image, but replacing the image 30 times per second costs about 40% of a core on an M2 Max, although drawing the image itself takes under 1%. `SpectrumView.swift` draws with Core Animation layers instead:

- the button gets a blank image of the spectrum's size, which keeps room before the title
- a layer-hosting `NSView` sits over that image, with one `CALayer` per bar segment and peak mark
- each frame only moves those layers, inside a `CATransaction` with actions disabled, so the button keeps its title and size and nothing else is laid out again
- the view lets clicks through (`hitTest` returns nil), so the button still opens its menu

The 30 fps timer runs in the run loop's common modes, so the spectrum keeps moving while the menu is open (`SpectrumController.swift`).

## Development

- `make debug` builds with debug logging on stdout. This build is named NowPlaying Debug, with the bundle ID `com.jf.nowplaying.debug`: macOS keeps its permissions apart from the installed app's, and reopens this build, not the installed one, after a permission change
- `make dev` builds it and runs it with its log in the terminal until it quits from its menu; Ctrl-C leaves it running. It starts the app through `open`: starting the binary directly would make macOS send permission requests to the terminal instead of NowPlaying
- `make test` runs the unit tests

## License

MIT License - see [LICENSE](LICENSE) file.
