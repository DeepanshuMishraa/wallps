# Wallps

Separate wallpapers for your desktop and lock screen on macOS 13+.

Project homepage: https://deepanshumishraa.github.io/wallps/ · [Changelog](https://deepanshumishraa.github.io/wallps/changelog/)

macOS always draws the lock screen from the desktop wallpaper, and there is no
setting to split them. Wallps gives you both anyway. Your lock screen always
shows the **lock screen wallpaper** and your desktop always shows the
**desktop wallpaper**, with no flash on any lock: the shortcut, the screen
saver, sleep or logout.

## Features

- Desktop and lock screen wallpapers set independently
- No flash when you lock, and nothing to configure after setup
- Live lock screens from your own videos or Apple's 4K aerials (macOS 26+)
- Built-in browser for Apple's wallpapers and aerials, grouped by macOS release and theme
- Swap the two wallpapers in one click, from the window or the menu bar
- Menu bar control: see both wallpapers, swap, browse, pause, and toggle Launch at Login
- Optional Launch at Login: starts hidden and keeps working after every reboot
- Multiple displays, drag and drop, and an optional hidden Dock icon

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
(`Wallps-1.1.1-macos.dmg`), open it, and drag `Wallps.app` into `Applications`.

The app is not signed or notarized, so Gatekeeper blocks it. Approve it once:

```sh
sudo xattr -rd com.apple.quarantine /Applications/Wallps.app/
```

Then open Wallps, pick a wallpaper for Desktop and one for Lock Screen, press
**Apply**, and turn on **Launch at login** in Settings so it keeps working
after reboots. Lock your Mac with `⌃⌘Q` to see it in action.

## Notes

- Turn on **Launch at login**. Automatic switching after a reboot needs it. Without it, open Wallps after every restart.
- Closing the window hides Wallps to the menu bar, where it keeps working. Use **Quit Wallps** in the menu to stop it.
- Quit Wallps and the desktop returns to standard macOS behavior. Reopen it and your setup comes back automatically.
- On older macOS versions Wallps also installs the legacy login image (one admin prompt) so the boot login window uses it.
- With FileVault, no app can customize the pre-boot unlock screen.

## Fonts

The app bundles [Geist Serif](https://vercel.com/font) and Cove, both under the
SIL Open Font License. The licenses ship in `Resources/Fonts`.
