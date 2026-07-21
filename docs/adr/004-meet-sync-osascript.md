# ADR-004: Use osascript subprocesses for Google Meet sync

**Date:** 2026-07-10
**Status:** Accepted

## Context

Syncing the mute state to Google Meet requires either controlling a Chrome tab (JS execution) or sending a keyboard shortcut to the Meet PWA process. Three approaches were evaluated:

**Approach A — NSAppleScript from the app binary**
`NSAppleScript` requires the `com.apple.security.automation.apple-events` entitlement and TCC permission tied to the binary's code signature hash. With ad-hoc signing, every rebuild changes the hash, so the permission granted to the previous build is lost. Users were prompted on every app launch.

**Approach B — CGEvent for the PWA, NSAppleScript for Chrome tabs**
`CGEvent` requires Accessibility permission (`AXIsProcessTrusted`), also tied to the binary hash. Same problem as Approach A, plus an additional permission type.

**Approach C — osascript subprocess for both paths**
`/usr/bin/osascript` is a system binary with its own stable TCC grants. Spawning it as a `Process()` subprocess inherits the user session and requires no permissions from the app binary itself.

## Decision

Use `Process()` + `/usr/bin/osascript` for all AppleScript execution:

- **Chrome tab:** JS injection via `execute tab javascript` to click the mic button by `aria-label`
- **Meet PWA:** `System Events` → `tell process "app_mode_loader"` → `keystroke "d" using command down`
- **Inbound polling:** same subprocess pattern, reading the `aria-label` every 500ms

The PWA sync fires only when no Chrome Meet tab is found, to avoid double-toggling (the PWA appears as a Chrome tab in AppleScript's model, so the JS path already covers it in most cases).

## Consequences

- No Accessibility or Apple Events permission is required from the app binary. The repeated macOS permission dialog on launch is eliminated permanently.
- Subprocess spawning adds ~50–100ms latency per sync call. This is acceptable given the use case (mute toggle is not latency-sensitive).
- The `WaveMute.entitlements` file is no longer embedded at signing time.
- If Apple restricts osascript's TCC grants in a future macOS version, this approach would break and would need to be revisited.
- Only Google Chrome is supported. Firefox and Safari do not expose `execute tab javascript` via AppleScript.
