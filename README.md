# Ordinary Notch Free

The Free edition of Ordinary Notch for macOS 14 and later, published under the MIT license.

Includes music playback and synced lyrics, timer and stopwatch, calendar and reminders, camera mirror, file shelf, opt-in clipboard history, personal GPT and Claude activity and questions, battery notices, and read-only fan and temperature monitoring. It adapts to a physical notch or Dynamic Island presentation.

This repository contains Free source only. Face Unlock, fan control and its privileged helper, separate Work accounts, VPN integration, eye and water reminders, membership services, and the commercial updater are not included. The commercial app is maintained separately. This repository starts with a clean history; it is not a mirror of the commercial repository.

## Build

Requires a Mac and Xcode with Swift 5.9 or newer. No paid service or premium repository is required to build.

```sh
swift test
python3 scripts/build-app.py
```

The bundle is written to `build/Ordinary Notch Free.app`. Open it manually. The script does not install or launch it. Local builds use ad-hoc signing; set `SIGNING_IDENTITY` to your own signing identity if needed. Notarization and binary release publishing are separate steps.

The bundle identifier is `dev.ordinary.notch.free`, with its own preferences and macOS permissions. Run one edition at a time: both can monitor the same players and agent sessions. Camera, calendar, reminders, Accessibility and Claude hooks are enabled from Settings when needed. Clipboard history is off by default and held in memory.

The included MediaRemote adapter uses macOS private playback APIs, which may change with macOS releases. Player automation supplies a fallback. Lyrics availability and timing depend on upstream providers; the Musixmatch integration is unofficial, with LRCLIB as fallback.

## Development

Use `development` for changes and merge tested work into `main`. GitHub Actions builds and tests the Free app on macOS. A commit does not automatically publish an installer or update installed apps. Free and commercial changes are maintained separately; there is no automatic source export.

Before publishing additions, run `python3 scripts/check-source-scope.py`. The file manifest and forbidden-feature checks guard the Free boundary, but changes still require review.

## License and acknowledgments

Original project code is MIT licensed; see [LICENSE](LICENSE). Third-party work retains its own license: the MediaRemote adapter is BSD-3-Clause, the Apple Hello adaptation and clipboard references have notices in `Resources`. Provider logos and product names identify their respective owners; this project is not affiliated with OpenAI, Anthropic, Spotify, Apple, or Musixmatch.
