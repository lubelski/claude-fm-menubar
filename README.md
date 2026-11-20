# Claude FM menu bar

A macOS menu bar app that plays [Claude FM](https://clau.de/radio), Anthropic's 24/7 lo-fi stream on YouTube.

This is a personal project, not affiliated with Anthropic. The music belongs to the stream and its artists.

- **Click** the radio icon for the menu: play/stop, volume, reconnect, a **Links** submenu, and an **Options** submenu with Click to Play, Stop When Other Audio Plays, Launch at Login, and Quit. A release build also has Check for Updates… and Update Automatically there.
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

## Releases and updates

A release build updates itself with [Sparkle](https://sparkle-project.org). It checks the feed about once a day, downloads a newer build, verifies its signature, and relaunches into it. While the stream is playing, the relaunch waits until playback stops. **Options > Update Automatically** turns this off.

```sh
./scripts/release.sh 1.2.0            # build, sign, notarize, and publish v1.2.0 from main
./scripts/release.sh 1.2.0 --dry-run  # build the files into build/release and publish nothing
```

The script publishes a GitHub Release with two files: the zipped app and `appcast.xml`, the feed. Installed copies read the feed from the latest release, so publishing the release ships the update. The one-time setup (a Developer ID certificate, a notarization login, and a Sparkle signing key) is described at the top of the script.

- The version is the release tag. The build number is the commit count, and Sparkle compares build numbers, so releases are built from `main`.
- A build from `bundle.sh` alone has no feed and never updates itself, so a development copy is not replaced by a release.
- The Sparkle signing key is the one AI Meter uses. Its public half is in `scripts/sparkle-public-key.txt`.

## License

MIT. See [LICENSE](LICENSE).
