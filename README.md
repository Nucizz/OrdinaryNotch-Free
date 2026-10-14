# Ordinary Notch Free

The Free edition of Ordinary Notch for macOS 14 and later, published under the MIT license.

Includes music playback and synced lyrics, timer and stopwatch, calendar and reminders, camera mirror, file shelf, opt-in clipboard history, personal GPT and Claude activity and questions, battery notices, and read-only fan and temperature monitoring. It adapts to a physical notch or Dynamic Island presentation.

This repository contains Free source only. Keep Awake, Face Unlock, fan control and its privileged helper, separate Work accounts, VPN integration, eye and water reminders, membership services, and the commercial updater are not included. The commercial app is maintained separately. This repository starts with a clean history; it is not a mirror of the commercial repository.

## Download the app

[Download Ordinary Notch for Mac](https://ordinary-notch-api.ordinary-notch-backend.workers.dev/download), or browse [official releases](https://github.com/Nucizz/OrdinaryNotch-Free/releases). Downloads and in-app updates use the same release files.

The compiled app includes free features and optional paid Pro features. This repository’s MIT license covers the published Free source only; proprietary Pro components in the compiled app are not licensed under MIT. Premium source remains private. GitHub’s automatic “Source code” archives contain this Free source, not the full source of the compiled app.

Releases are built from the private app repository and signed for Sparkle updates. Downloads currently use ad-hoc signing and are not Apple notarized. See the [website FAQ](https://ordinarynotch.vercel.app/#faq) for macOS opening instructions.

## Build

Requires a Mac and Xcode 27 or later. The app still runs on macOS 14 or later; Liquid Glass uses the newer system appearance when available. No paid service or premium repository is required to build.

```sh
swift test
python3 scripts/build-app.py
```

The bundle is written to `build/Ordinary Notch Free.app`. Open it manually. The script does not install or launch it. Local builds use ad-hoc signing; set `SIGNING_IDENTITY` to your own signing identity if needed. Notarization and binary release publishing are separate steps.

The bundle identifier is `dev.ordinary.notch.free`, with its own preferences and macOS permissions. Run one edition at a time: both can monitor the same players and agent sessions. Camera, calendar, reminders, Accessibility and Claude hooks are enabled from Settings when needed. Clipboard history is off by default and held in memory.

The included MediaRemote adapter uses macOS private playback APIs, which may change with macOS releases. Player automation supplies a fallback. Lyrics use LRCLIB by default. You can add your own Musixmatch API key in Media settings; it is stored in the Free app’s separate Keychain entry, with LRCLIB as fallback. Provider availability depends on their services and your API plan.

## Build without Actions

Run all checks and package a Free ZIP on your Mac:

```sh
python3 scripts/release-local.py
```

Use `--check` to run only the source audit and tests. Preparation leaves `build/free-v0.2.0/` with the ZIP, SHA-256 checksums, and source metadata. Temporary app bundles and build caches are removed. It does not install or launch the app. A build made with uncommitted changes is marked local-only; commit before preparing a package intended for publication.

Maintainers can publish a prepared clean build directly, without starting Actions:

```sh
gh auth login
python3 scripts/release-local.py --publish --resume build/free-v0.2.0
```

The account needs repository write access. Uploads use a draft and verify asset sizes and SHA-256 before publication. Failed uploads keep the local package for retry. Successful uploads remove the local release files. Free releases use `free-v…` tags and are never marked as the official latest release. Official `v…` releases and the commercial update feed remain separate.

## What changed in Free 0.2.0

- Native settings sidebar with colorful category icons, tab customization, and previews using the same views and proportions as the notch.
- Timer presets accept exact durations from `00:00:01` through `23:59:59`; Apple Clock must confirm the selected duration before starting.
- Default media player selection, current-device audio output menus, seek controls, album colors while paused, and an improved lyrics microphone button.
- Camera preview in Settings, photo capture, and a Photo Booth button that releases the notch camera before opening Photo Booth.
- Lock-screen media, timers, stopwatch, and personal agent details in a stack with soft scroll edges. Playback, seeking, and output switching work while locked; approvals and replies require unlocking. Choose None in General if you do not want task details visible while locked.
- Native glass clipboard panel, immediate single-option answers, unclipped button hover effects, delayed hints, and consistent notch button sizing.
- Single-pulse haptics, five-second welcome timeout without opening Settings, and event-driven Clock and agent monitoring.
- Closing the lid pauses playback and temporarily mutes the output; reopening restores its prior mute state without resuming playback. It does not prevent sleep.

No premium implementations or private repository history are included.

## Development

Use `development` for changes and merge tested work into `main`. GitHub Actions builds and tests the Free app on macOS. A commit does not automatically publish an installer or update installed apps. Free and commercial changes are maintained separately; there is no automatic source export.

Before publishing additions, run `python3 scripts/check-source-scope.py`. The file manifest and forbidden-feature checks guard the Free boundary, but changes still require review.

## License and acknowledgments

Original project code is MIT licensed; see [LICENSE](LICENSE). Third-party work retains its own license: the MediaRemote adapter is BSD-3-Clause, the Apple Hello adaptation and clipboard references have notices in `Resources`. Provider logos and product names identify their respective owners; this project is not affiliated with OpenAI, Anthropic, Spotify, Apple, or Musixmatch.
