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

## Usage

1. Launch the app - appears as ♫ in menu bar
2. Grant Spotify automation permission when prompted
3. Music info updates automatically every second using AppleScript

Right-click menu bar icon for auto-start and quit options.

## License

MIT License - see [LICENSE](LICENSE) file.
