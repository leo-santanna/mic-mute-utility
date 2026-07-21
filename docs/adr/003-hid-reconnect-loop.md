# ADR-003: Reconnect HID device automatically on USB re-enumeration

**Date:** 2026-07-14
**Status:** Accepted

## Context

`HIDMonitor` opens the HID device handle once on app launch. On macOS logout/login, USB devices are torn down and re-enumerated by the kernel. The existing handle becomes stale — `hid_read` returns `0` forever and `hid_write` silently fails — while the app continues running. Users had to quit and reopen WaveMute after every login to restore mute functionality.

## Decision

Restructure `HIDMonitor.loop()` as an outer reconnect loop wrapping an inner session loop:

- The outer loop calls `hid_open` at the top. If the device is unavailable, it waits 2 seconds and retries.
- The inner `runSession()` loop reads and writes on the open handle. It exits when a hard read error (`< 0`) or 50 consecutive empty reads (~5 seconds of heartbeat silence) is detected.
- On exit from `runSession()`, the outer loop closes the handle and loops back to `hid_open`.

The `hid_write` return value is now checked; a failed write increments the empty-read counter to trigger reconnect faster.

## Consequences

- WaveMute recovers automatically after logout/login with no user action required.
- There is a ~2 second gap after reconnection during which mute commands may be dropped. This is acceptable given the use case (startup after login).
- If the device is physically unplugged and replugged, the same reconnect logic applies.
- The 50-read threshold (~5 seconds at 100ms per read) was chosen to be long enough to tolerate brief USB bus pauses but short enough to detect genuine disconnections quickly.
