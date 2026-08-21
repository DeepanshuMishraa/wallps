# Wallps

Separate wallpapers for your desktop and lock screen on macOS 13+.

macOS always renders the lock screen from the desktop wallpaper — there is no
setting to split them. Wallps gives you both anyway: pick an image for each.
Your lock screen always shows the **lock screen image**, and your desktop
always shows the **desktop image** — zero flashing, on every lock: shortcut,
screen saver, sleep, or logout.

## Features

- Desktop and lock screen images set independently
- macOS 13+
- Zero-flash switching — nothing to configure after setup
- Menu bar control: see both file names, Set / Refresh, toggle Login Item, open or quit
- Optional *Launch at login*: starts hidden, keeps everything armed after every reboot
- Multi-display support, drag & drop image selection

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)

## Build

```sh
xcodebuild -project Wallps.xcodeproj -scheme Wallps -configuration Release -destination 'platform=macOS' build
```

Or open `Wallps.xcodeproj` in Xcode and press Run.

## Install

Download the [latest release](https://github.com/DeepanshuMishraa/wallps/releases/latest)
(`Wallps-1.0.1-macos.dmg`), open it, and drag `Wallps.app` into `Applications`.

The app is not signed or notarized, so Gatekeeper blocks it. Approve it once:

```sh
sudo xattr -dr com.apple.quarantine /Applications/Wallps.app
```

Then open Wallps, pick an image for Desktop and one for Lock screen, press
**Set wallpapers**, and turn on **Launch at login** so it keeps working after
reboots. Lock your Mac with `⌃⌘Q` to see it in action.

## Notes

- Turn on **Launch at login** — it's required for automatic switching after reboots. Without it, open Wallps after every restart.
- Closing the window hides Wallps to the menu bar, where it keeps working; use **Quit** in the menu to fully stop it.
- Quit Wallps and the desktop returns to standard macOS behavior; reopen it and your setup is restored automatically.
- On older macOS versions Wallps also installs the legacy login image (one admin prompt) so the boot/login window honors it.
- With FileVault, the pre-boot unlock screen cannot be customized — no app can reach it.