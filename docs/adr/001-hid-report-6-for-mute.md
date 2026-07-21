# ADR-001: Use HID Output Report 6 for mute control

**Date:** 2026-07-08
**Status:** Accepted

## Context

The Insta360 Wave USB microphone communicates with the official Wave Controller app over a proprietary Mavlink-based protocol tunnelled through HID Report ID 3 (vendor usage page `0xFF00`). That channel requires cloud authentication — the app exchanges a session token with Insta360's servers before the device accepts any control commands.

The goal was to mute the microphone from a third-party app without depending on Insta360's cloud infrastructure or reverse engineering the full authentication handshake.

Three paths were investigated:

1. **Mavlink vendor channel (Report ID 3, msg 0x2B `SetMicMute`)** — requires cloud auth. Disassembly of `PSP::HidMavlinkController` confirmed the session token requirement. Not viable.
2. **CoreAudio `kAudioDevicePropertyMute`** — mutes the mic at the OS level. Works, but meeting apps (Google Meet, Teams) detect it as a "system mute" and show warnings. Also affects all apps system-wide.
3. **HID Output Report 6** — discovered empirically by testing all output report IDs from the HID descriptor. `[0x06, 0x01]` mutes the audio gate and turns the front LED red at the firmware level. No authentication required.

## Decision

Use HID Output Report 6 (`[0x06, 0x01]` = mute, `[0x06, 0x00]` = unmute) as the sole mute mechanism.

## Consequences

- Mute is hardware-level and microphone-specific; it does not trigger a system-wide mute.
- The device's front LED reflects the state correctly, matching the official app's behaviour.
- No cloud dependency or internet access required.
- The official Wave Controller app, if running simultaneously, will also open the HID device. Since hidapi uses exclusive access on macOS, only one app can hold the device at a time. WaveMute and the official app cannot run simultaneously without conflict.
- Report 6 causes the device to briefly mirror its state through the USB Audio Class mute control. This is addressed by ADR-002.
