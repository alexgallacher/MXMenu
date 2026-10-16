# MXMenu

A small macOS menu-bar app for the Logitech MX Master 4 (and 3 / 3S). It talks to the mouse directly over Logitech's HID++ protocol, so it works without Logi Options+.

From the menu bar you can see the battery level and charging state, set the pointer speed, switch the scroll wheel between ratchet and free spin, tune SmartShift, and reverse the wheel direction on the mouse only (so the trackpad keeps natural scrolling). The middle, back, forward and thumb gesture buttons can be remapped to Mission Control, App Exposé, Show Desktop, switching Desktops, Back / Forward, Play / Pause, an area screenshot, copy, paste or undo.

Your settings are re-applied whenever the mouse wakes up or reconnects. It works over Bluetooth or a Logi Bolt / Unifying receiver.

## Install

1. Download `MXMenu.zip` from the [latest release](../../releases/latest) and unzip it.
2. Drag `MXMenu.app` into your Applications folder.
3. Open it. The app isn't notarised by Apple, so the first time macOS will say it can't verify the developer. Click **Done**, then go to **System Settings › Privacy & Security**, scroll down and click **Open Anyway**. (Or run `xattr -dr com.apple.quarantine /Applications/MXMenu.app` in Terminal.)
4. A mouse icon with the battery percentage appears in the menu bar.

Quit Logi Options+ first. Both apps change the same mouse settings and fight over the buttons.

Turn on **Launch at login** at the bottom of the panel to start it automatically.

## Permissions

- **Accessibility** is requested the first time you remap a button (System Settings › Privacy & Security › Accessibility). It's needed to catch mouse buttons and send shortcuts.
- **Input Monitoring** may be requested the first time the app opens the mouse.

The app is ad-hoc signed, so after an update macOS may ask for Accessibility again. If remapping stops working, remove MXMenu from the Accessibility list and add it back.

## Build from source

You need macOS 14 or later and Xcode or the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/alexgallacher/MXMenu.git
cd MXMenu
./build-app.sh
cp -R build/MXMenu.app /Applications/
open /Applications/MXMenu.app
```

For development you can also run `swift run --build-system native`, or open `Package.swift` in Xcode. Launch at login and updates only work from the built `.app`.

Every push is also built on a Mac by GitHub Actions; the built `MXMenu.zip` is attached to each run.

## Updates

MXMenu updates itself from this repo's [GitHub Releases](../../releases). It checks shortly after launch and every 6 hours. You can check by hand or turn automatic installs off from the ••• menu.

To publish a new version, commit your changes and run:

```bash
./release.sh 0.2.0
```

That tags the commit and pushes the tag. GitHub Actions builds the app with that version and creates the release with `MXMenu.zip` attached. Bumping `CFBundleShortVersionString` in `Support/Info.plist` and pushing to `main` releases that version too.

## How it works

The app finds Logitech HID++ interfaces with IOKit (vendor usage page `0xFF43` over Bluetooth, `0xFF00` on receivers) and sends HID++ 2.0 requests:

| Feature | ID | Used for |
| --- | --- | --- |
| Device name | `0x0005` | Finding the MX Master |
| Unified battery / battery status | `0x1004` / `0x1000` | Battery level and charging |
| Adjustable DPI | `0x2201` | Pointer speed |
| SmartShift (enhanced) | `0x2111` / `0x2110` | Ratchet, free spin, SmartShift threshold |
| Hi-res wheel | `0x2121` | Reverse scroll direction |
| Reprogrammable controls | `0x1B04` | Diverting the gesture button (control `0x00C3`) |

Middle, back and forward are remapped with a `CGEventTap`, so those remaps apply to every mouse connected to the Mac.

## Known limits

- The MX Master 4's haptic Actions Ring button may use a different control ID from the gesture button. The app logs every control the mouse exposes: open Console.app and filter on `MXMenu` to see them.
- If the mouse only exposes the newer DPI feature (`0x2202`), the pointer speed picker won't appear.
