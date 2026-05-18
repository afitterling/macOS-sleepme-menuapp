# Sleep Timer

A tiny macOS menu-bar app that puts the Mac to sleep after a chosen delay
(5 min, 15 min, 30 min, 1 h, 2 h) — or immediately. Single-file Swift app,
no Xcode project, no dependencies.

## Requirements

- macOS 11+
- Command Line Tools for Xcode (`xcode-select --install`) — provides
  `swiftc`, `codesign`, and `pkgbuild`.

## Build

```sh
./build.sh
```

The script produces two artifacts under `build/`:

| Artifact                 | Purpose                                           |
| ------------------------ | ------------------------------------------------- |
| `SleepTimer.app`         | The runnable app bundle (ad-hoc signed).          |
| `SleepTimer-1.0.pkg`     | Component installer that drops the app into `/Applications`. |

What the script does, step by step:

1. Wipes and recreates `build/`.
2. Compiles `main.swift` with `swiftc -O` into
   `SleepTimer.app/Contents/MacOS/SleepTimer`.
3. Writes a minimal `Info.plist` (LSUIElement = true so it stays out of the
   Dock).
4. Ad-hoc signs the bundle with `codesign --sign -` so Gatekeeper doesn't
   refuse to launch the unsigned binary on first run.
5. Stages the bundle into `build/pkg-root/Applications/` and runs
   `pkgbuild --install-location /` to emit `SleepTimer-1.0.pkg`.

## Install

Double-click `build/SleepTimer-1.0.pkg` and follow the installer — it places
`SleepTimer.app` in `/Applications`. Launch it from Spotlight or
Finder; the moon-zzz icon appears in the menu bar.

Alternatively, just drag `build/SleepTimer.app` into `/Applications`.

## Run from source

```sh
./build.sh && open build/SleepTimer.app
```

To quit: click the menu-bar icon → Quit (or `⌘Q` with the menu open).

## Bump version

Edit `VERSION` at the top of `build.sh` — it flows into both the app's
`Info.plist` and the `.pkg` filename / identifier metadata.

## License

GPLv3 — see [LICENSE](LICENSE).
