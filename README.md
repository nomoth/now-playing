# NowPlaying

A lightweight macOS menu bar application that displays currently playing Spotify track information.

## Features

- Displays artist and track name in the menu bar
- Visual indicators for playing (♫) and paused (❚❚) states  
- On macOS 26+, a spectrum analyzer of Spotify's audio in place of ♫ while playing
- Auto-start at login option
- Updates by polling Spotify through AppleScript: every second while playing, every 3 seconds while paused

## Requirements

- macOS 11.0+
- Spotify installed
- Xcode or the Command Line Tools, to build

## Installation

```bash
git clone https://github.com/yourusername/now-playing.git
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

Click the menu bar item for the Start at Login and Quit options.

### Spectrum analyzer

On macOS 26 and later, the ♫ symbol becomes a spectrum analyzer while Spotify plays. It captures Spotify's audio through Core Audio, so macOS asks once for permission to capture other apps' audio; nothing is recorded or stored. If the bars stay flat while music plays, check that NowPlaying is allowed in System Settings > Privacy & Security > Screen & System Audio Recording.

Band count, frequency range, sensitivity and motion are set in `AppConfig.swift`.

## Development

- `make debug` builds with debug logging on stdout
- `make dev` builds it and runs it with its log in the terminal until it quits from its menu; Ctrl-C leaves it running. It starts the app through `open`: starting the binary directly would make macOS send permission requests to the terminal instead of NowPlaying
- `make test` runs the unit tests

## License

MIT License - see [LICENSE](LICENSE) file.
