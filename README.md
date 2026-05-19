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

## Install to /Applications

Pick whichever you prefer — all three end up with `SleepTimer.app` in
`/Applications`. Launch it from Spotlight or Finder and the moon-zzz icon
appears in the menu bar.

**Installer (GUI).** Double-click `build/SleepTimer-1.0.pkg` and click
through the prompts.

**Installer (CLI).** Useful for scripted setup:

```sh
sudo installer -pkg build/SleepTimer-1.0.pkg -target /
```

**Manual copy.** No installer at all:

```sh
cp -R build/SleepTimer.app /Applications/
```

> First launch: because the bundle is only ad-hoc signed (not notarized),
> Gatekeeper may complain. Right-click the app in Finder → **Open**, then
> confirm in the dialog. Subsequent launches are silent.

To start it automatically at login: System Settings → General → Login Items
→ **+** → pick `/Applications/SleepTimer.app`.

### Uninstall

```sh
pkill -x SleepTimer
rm -rf /Applications/SleepTimer.app
sudo pkgutil --forget tech.sp33c.sleeptimer   # only if installed via .pkg
```

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
