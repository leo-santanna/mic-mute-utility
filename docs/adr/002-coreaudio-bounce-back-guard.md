# ADR-002: Subscribe to CoreAudio mute property and immediately reset it

**Date:** 2026-07-08
**Status:** Accepted

## Context

Writing HID Output Report 6 (see ADR-001) causes the Wave USB device to briefly reflect its mute state through the USB Audio Class mute control. macOS CoreAudio exposes this as `kAudioDevicePropertyMute` on the input device. Meeting apps (Google Meet, Microsoft Teams, Zoom) subscribe to this property and display a "microphone muted by system" warning whenever it becomes `1`.

This created a regression: WaveMute muted the mic cleanly at the hardware level, but users still received the warning banner in Meet.

## Decision

Subscribe to `kAudioDevicePropertyMute` on the Wave USB input device via `AudioObjectAddPropertyListenerBlock`. Whenever the value changes to `1` (muted), immediately reset it to `0` via `AudioObjectSetPropertyData`.

The subscription fires on the main dispatch queue. The reset happens synchronously within the same callback. This is fast enough that meeting apps never observe the muted state.

## Consequences

- Meeting apps no longer show "microphone muted by system" warnings when WaveMute mutes.
- The CoreAudio mute property for the Wave device is effectively locked at `0` for the lifetime of the app. Any other process attempting to read the device's CoreAudio mute state will always see `0` (unmuted), regardless of the actual hardware gate state.
- This is intentional: the source of truth for mute state is the HID heartbeat (byte[29]), not CoreAudio.
- If macOS or a future app relies on CoreAudio mute state to indicate "this device is hardware-muted", it will not receive that signal while WaveMute is running.
