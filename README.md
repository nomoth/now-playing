# NowPlaying

A lightweight macOS menu bar application that displays currently playing Spotify track information.

## Features

- Displays artist and track name in the menu bar
- Visual indicators for playing (♫) and paused (❚❚) states  
- Auto-start at login option
- Real-time updates via periodic polling (every second)

## Requirements

- macOS 11.0+
- Spotify installed

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
3. Music info updates automatically every second using AppleScript

Right-click menu bar icon for auto-start and quit options.

## License

MIT License - see [LICENSE](LICENSE) file.
