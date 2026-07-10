# Google Meet sync - investigation notes

This document captures the approaches considered, the one chosen for prototyping, open questions, and what needs to be validated before this feature ships.

## Goal

When the user mutes the Wave mic (via hotkey, physical button, or menu), also mute the microphone inside any active Google Meet call in Chrome, so the two states stay in sync.

## Approaches considered

### 1. JavaScript injection via Chrome AppleScript (chosen)

AppleScript can instruct Chrome to execute arbitrary JavaScript on a specific tab:

```applescript
tell application "Google Chrome"
    execute tab 1 of window 1 javascript "document.querySelector('button').click()"
end tell
```

**Pros:**
- No extra macOS permissions required (no Accessibility, no screen recording)
- Works regardless of which window or app is focused
- Chrome AppleScript support is stable and well-documented

**Cons:**
- Only works in Google Chrome, not other browsers
- The DOM selector could break if Meet changes its internal markup
- Requires the `com.apple.applescript` entitlement (standard, not restricted)

**Selector chosen:** `button[aria-label*="Turn off microphone"]` / `button[aria-label*="Turn on microphone"]`

The `aria-label` attribute is Meet's accessibility label for the mic button and is more stable than internal attributes like `jsname` or `data-*`. The label text flips with the mute state, so we match by the label of the *action we want to perform*, not the current state.

### 2. Keyboard shortcut Cmd+D via CGEvent

Google Meet's documented keyboard shortcut for toggling the microphone is `Cmd+D`. We could synthesise this key event and send it to Chrome.

**Pros:**
- Uses Meet's own official API surface, most future-proof selector-wise
- Unlikely to break with Meet DOM changes

**Cons:**
- Requires Accessibility permission (`AXIsProcessTrusted`), which shows a system dialog and must be granted by the user in System Settings
- Only works when the Meet tab is the active/focused window
- Adding Accessibility permission significantly increases the app's trust surface

**Verdict:** viable fallback but too disruptive as the primary approach.

### 3. Chrome DevTools Protocol (CDP)

Chrome exposes a full automation API over a local WebSocket when launched with `--remote-debugging-port`. This would let us call `Input.dispatchMouseEvent` or `Runtime.evaluate` with full reliability.

**Verdict:** not viable for end users — requires Chrome to be launched with a non-default flag.

## Implementation

`MeetSync.swift` implements approach 1. It is called from `AppDelegate.toggleMute()` after the HID mute is applied.

The flow:
1. Build an AppleScript that iterates all Chrome windows and tabs
2. For any tab whose URL contains `meet.google.com`, execute the JS click
3. JS finds the mic button by `aria-label` matching the desired transition
4. Returns `"clicked"` if successful, `"not_found"` if the button wasn't found

Errors are silently swallowed — if Meet is not open, nothing happens.

## Open questions before shipping

- [ ] **Selector stability**: validate `aria-label*="Turn off/on microphone"` still works across Meet UI updates. The label text is English-only — needs testing with non-English Chrome locales.
- [ ] **Reverse sync**: if the user mutes *inside* Meet (clicking the button or pressing Cmd+D), does the Wave mic LED update? Currently it does not. Full bidirectional sync would require polling Meet's mute state, which is a more complex problem.
- [ ] **Firefox / Safari**: users on other browsers get no sync. Should we add a Cmd+D fallback for focused Meet tabs?
- [ ] **Meet PWA**: if Meet is installed as a Progressive Web App, the window host is not `Google Chrome` — needs a separate handler.
- [ ] **Privacy disclosure**: the app gains access to execute JS on the user's Chrome tabs. This should be clearly communicated in the README and the app's first-run experience.
- [ ] **AppleScript entitlement**: verify the unsigned/ad-hoc build can use `NSAppleScript` without additional entitlements on macOS 14+.

## Testing plan

1. Open a Google Meet call in Chrome
2. Confirm mic is unmuted (green mic icon in Meet)
3. Press F9 in WaveMute
4. Verify: Wave LED goes red AND Meet mic button goes to muted state
5. Press F9 again
6. Verify: Wave LED goes green AND Meet mic button returns to active state
7. Mute via physical button on the mic
8. Verify: Meet does NOT sync (reverse sync is out of scope for this iteration)
