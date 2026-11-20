# Claude FM menu bar

A macOS menu bar app that plays [Claude FM](https://clau.de/radio), Anthropic's 24/7 lo-fi stream on YouTube.

This is a personal project, not affiliated with Anthropic. The music belongs to the stream and its artists.

- **Click** the radio icon for the menu: play/stop, volume, reconnect, a **Links** submenu, and an **Options** submenu with Click to Play, Stop When Other Audio Plays, Launch at Login, and Quit.
- **Right-click** (or Control-click) to play or stop. While playing, the icon is a waveform.

Turn on **Options > Click to Play** to swap them: click to play, right-click for the menu.

## How it plays

Claude FM is published only as a YouTube live stream. The app plays it through YouTube's embedded IFrame player, in a web view that is never shown. That keeps it to official YouTube playback with no extra dependencies.

The stream's video ID changes when the broadcast restarts. On first play, and on **Reconnect**, the app follows `https://clau.de/radio` to find the current one. If that fails, it falls back to the ID built into `StreamPlayer.swift`.

Stopping releases the stream. Playing again reloads it, so playback starts at the live edge instead of where you stopped.

## Stop When Other Audio Plays

When this option is on, playback stops after another app has been playing audio for about 2 seconds, so short alert sounds don't count. Apps that were already playing when you pressed play are ignored until they go quiet.

The app checks Core Audio's per-process list once a second. Its own audio comes out of a WebKit helper process, which it recognizes as its own through `responsibility_get_pid_responsible_for_pid`, a libSystem function that isn't in a public header. Some apps keep their audio output open while silent, and those can trigger it.

## Build

```sh
./scripts/bundle.sh            # builds build/Claude FM.app
./scripts/bundle.sh --install  # moves it to ~/Applications and launches it
```

Requires macOS 15 and Xcode or the Command Line Tools. For testing from a terminal, `CLAUDE_FM_AUTOPLAY=1` starts playback at launch, and state changes go to stderr.

## License

MIT. See [LICENSE](LICENSE).
