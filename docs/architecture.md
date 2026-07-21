# Architecture

This document describes the structure, components, and data flows of WaveMute. It is the primary reference for any Claude session or contributor working on the codebase.

---

## Overview

WaveMute is a macOS menu bar application (LSUIElement) with no main window. It runs permanently in the background and has three responsibilities:

1. Controlling the Insta360 Wave USB microphone mute state via HID
2. Keeping the menu bar icon and microphone LED in sync with the actual device state
3. Propagating mute state changes to and from Google Meet

---

## Device communication

### Device identifiers

| Property | Value |
|----------|-------|
| USB Vendor ID | `0x18F0` |
| USB Product ID | `0x4E40` |
| USB Product Name | `Insta360 Wave USB` |
| HID interface | Interface 3 (`bInterfaceClass 3`, `PrimaryUsagePage 0xFF00`) |

### Mute mechanism

The device is muted by writing **HID Output Report ID 6**:

- `[0x06, 0x01]` — muted (LED turns red, audio gated at firmware level)
- `[0x06, 0x00]` — unmuted

This controls both the audio gate and the front LED at the firmware level. No cloud authentication or Mavlink session is required. See [ADR-001](adr/001-hid-report-6-for-mute.md).

### State detection (physical button sync)

The device broadcasts a vendor heartbeat on Report ID 3 (type `0xEF`) every ~100ms. **Byte[29]** of this packet reflects the current mute state:

- `0x01` — muted
- `0x00` — unmuted

`HIDMonitor` reads this byte in a background thread and fires `onStateChanged` when it flips.

### CoreAudio bounce-back guard

Writing Report 6 causes the device to briefly mirror its state through the USB Audio Class mute control, which macOS CoreAudio exposes. Meeting apps detect this as a "system mute". `AppDelegate` subscribes to the CoreAudio `kAudioDevicePropertyMute` property and immediately resets it to `0` to prevent this. See [ADR-002](adr/002-coreaudio-bounce-back-guard.md).

---

## Component map

```
AppDelegate
├── HIDMonitor          background thread, HID read/write loop
├── MeetSync            Google Meet bidirectional sync
├── ShortcutRecorderWindowController   hotkey capture UI
└── AboutWindowController              about window UI

Standalone helpers
├── MenuBarIcons        SF Symbol icon rendering, beta badge
└── LaunchAtLogin       LaunchAgent plist install/uninstall
```

### AppDelegate

Central coordinator. Owns the `NSStatusItem`, the global hotkey (Carbon `RegisterEventHotKey`), the menu, and all component wiring. All mute toggle actions funnel through `toggleMute()`.

**Mute flow (outbound):**
```
toggleMute()
  -> HIDMonitor.sendMute(muted)      writes Report 6
  -> MeetSync.sync(muted)            syncs to Meet
  -> updateMenuBarIcon()             updates status bar
```

**Mute flow (physical button):**
```
HIDMonitor.onStateChanged(muted)
  -> AppDelegate: isMuted = muted
  -> MeetSync.sync(muted)
  -> updateMenuBarIcon()
```

**Mute flow (inbound from Meet):**
```
MeetSync.onExternalStateChange(muted)
  -> AppDelegate: isMuted = muted
  -> HIDMonitor.sendMute(muted)      hardware mute
  -> updateMenuBarIcon()
```

### HIDMonitor

Runs on a dedicated `Thread` (QoS `.utility`). Keeps the HID device open via `libhidapi` (loaded via `dlopen`). Reconnects automatically if the device disconnects (e.g. on logout/login). See [ADR-003](adr/003-hid-reconnect-loop.md).

Key properties:
- `onStateChanged` — called on main thread when byte[29] flips
- `sendMute(_ muted: Bool)` — thread-safe via `NSLock`, consumed on next loop iteration
- Suppression window (400ms) after each write prevents heartbeat flicker

### MeetSync

Handles bidirectional sync with Google Meet via `osascript` subprocesses. No Accessibility permission is required from the app binary. See [ADR-004](adr/004-meet-sync-osascript.md).

**Outbound:**
- Chrome tab: JS injection clicks the mic button by `aria-label`
- Meet PWA: `System Events` keystroke `Cmd+D` to `app_mode_loader`
- PWA path only fires when no Chrome Meet tab exists (to avoid double-toggling)

**Inbound (polling):**
- `Timer` fires every 500ms on main thread, dispatches read to background
- Reads mic button `aria-label` from any `meet.google.com` Chrome tab
- Suppression window (1.5s) prevents reacting to our own outbound syncs
- `onExternalStateChange` fires on main thread when state flips

**Meet PWA detection:**
- Bundle ID: `com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan`
- The PWA also appears as a Chrome tab in the AppleScript model, so JS injection handles it in most cases

### MenuBarIcons

Produces `NSImage` instances for the status item button.

- Unmuted: `mic.fill`, `isTemplate = true` (adapts to any menu bar background)
- Muted: `mic.slash.fill` with `.systemRed` palette color, `isTemplate = false`
- Beta builds (`-D BETA_BUILD`): composites a `β` badge in the bottom-right corner. Unmuted composite uses `isTemplate = true` so the background adapts correctly.

### LaunchAtLogin

Installs/uninstalls a LaunchAgent plist at `~/Library/LaunchAgents/com.local.WaveMute.plist`. Uses `launchctl load/unload` to activate immediately without a reboot.

---

## Bundle structure

```
WaveMute.app/
├── Contents/
│   ├── Info.plist
│   ├── MacOS/
│   │   └── WaveMute          compiled binary
│   ├── Frameworks/
│   │   └── libhidapi.dylib   bundled, rpath @executable_path/../Frameworks
│   └── Resources/
│       └── AppIcon.icns
```

The binary is ad-hoc signed (`codesign --sign -`). No entitlements are embedded. `libhidapi` is loaded at runtime via `dlopen` rather than linked, so the binary has no hard dependency on it.

---

## Persistence

All user preferences are stored in `UserDefaults` under `com.local.WaveMute`:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `shortcutKeyCode` | Int | 101 (F9) | Carbon key code |
| `shortcutModifiers` | Int | 0 | Carbon modifier flags |
| `shortcutDisplay` | String | "F9" | Human-readable label shown in menu |

---

## Build flags

| Flag | Effect |
|------|--------|
| `-D BETA_BUILD` | Adds β badge to menu bar icon |

Set automatically by `build.sh` when HEAD is not at an exact `vX.Y.Z` tag.

---

## Key constraints

- **No Accessibility permission required.** The Meet sync uses `osascript` subprocesses (system binary with its own TCC grants) instead of CGEvent.
- **No CoreAudio mute.** WaveMute never sets `kAudioDevicePropertyMute` intentionally; it only resets it to prevent the bounce-back.
- **libhidapi loaded at runtime.** `dlopen` is used so the binary runs even if libhidapi is missing (HID features simply no-op).
- **HID device opened exclusively.** Only one process can hold the device open at a time. If the official Insta360 Wave Controller app is running simultaneously, HID operations may fail silently.
