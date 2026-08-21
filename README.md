# Wallps

Separate wallpapers for your desktop and lock screen on macOS.

macOS always renders the lock screen from the desktop wallpaper — there is no
setting to split them. Wallps gives you both anyway: pick an image for each and
Wallps shows your **lock screen image** the moment your Mac locks (lock, screen
saver, logout) and swaps your **desktop image** back the moment you unlock.

## Features

- Desktop and lock screen images set independently
- macOS 13 through macOS 26 (Tahoe)
- Automatic, event-driven swapping — nothing to configure after setup
- Optional *Launch at login*: starts hidden, swap stays armed after every reboot
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

1. Copy the built `Wallps.app` into `/Applications`
2. Open Wallps, pick an image for Desktop and one for Lock screen, press **Set wallpapers**
3. Turn on **Launch at login** so the swap keeps working after reboots

Lock your Mac with `⌃⌘Q` to see it in action.

## Notes

- The swap runs while Wallps is running. Quit it and the lock screen mirrors the desktop again; reopen it and your choices are re-applied automatically.
- On macOS 13–25 Wallps also installs the legacy login image (one admin prompt) so the boot/login window honors it. macOS 26 renders the lock screen live from the desktop wallpaper, which is what the swap approach is built around.
- With FileVault, the pre-boot unlock screen cannot be customized — no app can reach it.