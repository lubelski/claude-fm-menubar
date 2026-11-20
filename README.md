# Claude FM menu bar

A macOS menu bar app that plays [Claude FM](https://clau.de/radio), Anthropic's 24/7 lo-fi stream on YouTube.

This is a personal project, not affiliated with Anthropic. The music belongs to the stream and its artists.

- **Click** the radio icon to play or stop. While playing, the icon is a waveform.
- **Right-click** (or Control-click) for the menu: play/stop, volume, reconnect, a **Links** submenu, and an **Options** submenu with click behavior, launch at login, and quit.

Under **Options > Click Behavior** you can swap the two, so a click opens the menu and a right-click plays or stops.

## How it plays

Claude FM is published only as a YouTube live stream. The app plays it through YouTube's embedded IFrame player, in a web view that is never shown. That keeps it to official YouTube playback with no extra dependencies.

The stream's video ID changes when the broadcast restarts. On first play, and on **Reconnect**, the app follows `https://clau.de/radio` to find the current one. If that fails, it falls back to the ID built into `StreamPlayer.swift`.

Stopping releases the stream. Playing again reloads it, so playback starts at the live edge instead of where you stopped.

## Build

```sh
./scripts/bundle.sh            # builds build/Claude FM.app
./scripts/bundle.sh --install  # moves it to ~/Applications and launches it
```

Requires macOS 15 and Xcode or the Command Line Tools. For testing from a terminal, `CLAUDE_FM_AUTOPLAY=1` starts playback at launch, and state changes go to stderr.

## License

MIT. See [LICENSE](LICENSE).
