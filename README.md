# WaveMute

A lightweight macOS menu bar utility that gives the **Insta360 Wave USB microphone** a proper global mute shortcut, with full LED feedback and two-way state sync.

[![CI](https://github.com/leo-santanna/mic-mute-utility/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/leo-santanna/mic-mute-utility/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-leonardoebi-FFDD00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/leonardoebi)

---

## Why this exists

The official Insta360 Wave Controller app provides a menu bar popup to mute the mic, but offers no global keyboard shortcut. This utility fills that gap with a minimal, always-on menu bar app you can assign any hotkey to, including dedicated mute keys found on many modern keyboards.

---

## Features

- **Global hotkey**: configurable, defaults to F9
- **Hardware-level mute**: mutes the mic at the device firmware level via HID Output Report 6, not through CoreAudio, so meeting apps (Google Meet, Teams, Zoom) don't show a "microphone muted by system" warning
- **LED sync**: the mic's front LED turns red when muted, exactly like the official app
- **Physical button sync**: muting/unmuting from the mic's built-in touch display is reflected immediately in the menu bar icon
- **Launch at login**: optional, toggled from the menu
- **No runtime dependencies**: `libhidapi` is bundled inside the app

---

## Requirements

- macOS 14 (Sonoma) or later
- Insta360 Wave USB microphone

---

## Installation

### Option A: build from source (recommended)

```bash
# 1. Install hidapi (build-time only, bundled into the app afterwards)
brew install hidapi

# 2. Clone and build
git clone https://github.com/leo-santanna/mic-mute-utility.git
cd mic-mute-utility
bash build.sh

# 3. Install
cp -r WaveMute.app /Applications/
xattr -cr /Applications/WaveMute.app   # clear Gatekeeper quarantine
open /Applications/WaveMute.app
```

### Option B: download a release

Download the latest `WaveMute.app.zip` from the [Releases](https://github.com/leo-santanna/mic-mute-utility/releases) page, unzip, and drag to `/Applications`. On first launch you may need to right-click > Open to bypass Gatekeeper (the app is ad-hoc signed, not notarized).

---

## Usage

Once running, a microphone icon appears in the menu bar:

| Icon | State |
|------|-------|
| `mic.fill` (white/black) | Unmuted |
| `mic.slash.fill` (red) | Muted |

**Toggle mute:** press the configured hotkey (default **F9**), click the mic's physical button, or use *Toggle Wave Mute* in the menu.

**Change the hotkey:** click the menu bar icon, then *Change Shortcut...*, press the key combination you want, and click *Save*.

**Launch at login:** click the menu bar icon and toggle *Launch at Login*.

---

## How it works

### Mute mechanism

The Insta360 Wave Controller app communicates with the mic over a proprietary Mavlink-based protocol tunnelled through USB HID (vendor usage page `0xFF00`, Report ID 3). That channel requires cloud authentication and is not publicly documented.

Through reverse engineering the HID descriptor and firmware behaviour, we found a simpler path:

- **HID Output Report 6** (`[0x06, 0x01]` = mute, `[0x06, 0x00]` = unmute) controls both the audio gate and the LED directly at the firmware level, with no authentication required.
- The device reflects its mute state in **byte[29]** of the periodic vendor heartbeat it broadcasts (Report ID 3, type `0xEF`). WaveMute reads this to stay in sync with physical button presses.
- Report 6 causes the device to briefly mirror its state through the USB Audio Class mute control (which macOS CoreAudio exposes), so meeting apps could detect a "system mute" event. WaveMute subscribes to that CoreAudio property and immediately resets it to `0`, so the OS never reports the mic as system-muted.

### Device identifiers

| Property | Value |
|----------|-------|
| USB Vendor ID | `0x18F0` (insta360) |
| USB Product ID | `0x4E40` |
| HID interface | Interface 3 (`bInterfaceClass 3`, `PrimaryUsagePage 0xFF00`) |
| Mute LED report | Output Report ID `0x06`, bit 0 |
| Mute state in heartbeat | Report ID `0x03`, type `0xEF`, byte offset 29 |

---

## Project structure

```
mic-mute-utility/
├── WaveMute/
│   ├── main.swift              # App entry point
│   ├── AppDelegate.swift       # Menu bar, hotkey, orchestration
│   ├── HIDMonitor.swift        # Persistent HID read/write loop
│   ├── ShortcutRecorder.swift  # Hotkey capture window
│   ├── MenuBarIcons.swift      # SF Symbol icon helpers
│   ├── LaunchAtLogin.swift     # LaunchAgent plist install/uninstall
│   ├── Info.plist              # Bundle metadata
│   └── AppIcon.icns            # App icon
├── icon.iconset/               # Source PNGs for the icon (all required sizes)
├── make_icon.swift             # Script to regenerate AppIcon.icns
├── build.sh                    # One-step build + bundle + sign script
└── README.md
```

---

## Building

```bash
bash build.sh
```

This compiles all Swift sources, bundles `libhidapi.dylib` from Homebrew into `WaveMute.app/Contents/Frameworks/`, sets the correct rpath, ad-hoc signs each component in dependency order, and clears the quarantine attribute.

To regenerate the app icon (e.g. after design changes):

```bash
swift make_icon.swift <size> <output.png>
```

---

## Reverse engineering notes

The investigation that led to this utility involved:

1. Identifying the device via `ioreg`: VID `0x18F0`, PID `0x4E40`
2. Decoding the HID report descriptor to map all input/output report IDs and their usages
3. Disassembling the Qt binary (`PSP::HidMavlinkController`, `PSP::PcMavlink`) to understand the vendor Mavlink protocol and mute command IDs (`SetMicMute` -> msg `0x2B`)
4. Empirically testing each HID output report to identify which one controls the LED and audio gate
5. Capturing the periodic heartbeat to find the byte that reflects device mute state
6. Discovering the CoreAudio bounce-back and implementing the property listener guard

---

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow, branch conventions, and commit message format.

Some areas that could be improved:

- **Notarized release**: sign with an Apple Developer certificate so users don't need to clear quarantine manually
- **Xcode project / SPM**: replace the `build.sh` script with a proper package structure
- **Other Insta360 devices**: the HID approach may work for other mics in the lineup with minor adjustments to report IDs or heartbeat byte offsets
- **Menu bar refinements**: show mic level, handle device disconnect/reconnect gracefully

Please open an issue before starting significant work so we can coordinate.

---

## License

MIT - see [LICENSE](LICENSE).

---

## Acknowledgements

- [hidapi](https://github.com/libusb/hidapi) - the HID library bundled at runtime
- Insta360 for building a microphone with accessible HID endpoints
