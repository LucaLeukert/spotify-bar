# Spotify Bar

A small native macOS menu bar controller for Spotify.

Spotify Bar uses Spotify's local AppleScript interface. It has no Spotify OAuth
flow, web service, analytics, or helper process.

## Features

- Current song and artist in a native menu bar menu
- Rounded album artwork
- Play/pause, next, and previous controls
- Copy the track URL or Spotify embed code
- Configurable title formatting and title cleanup
- Optional launch at login
- Notification-driven updates with a power-efficient fallback
- Automatically sleeps its fallback timer while Spotify is closed

## Build

1. Open `SpotifyBar.xcodeproj`.
2. Select the **SpotifyBar** scheme and your signing team.
3. Build and run.
4. Allow Spotify automation when macOS asks.

Requires macOS 14 or newer.

Spotify's AppleScript dictionary exposes playback, track metadata, and track
URLs. Like/dislike, playlist editing, Spotify Connect device selection, and
radio creation require other APIs and are intentionally not shown as fake menu
actions.

## License

MIT
