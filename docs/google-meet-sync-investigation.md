# Google Meet sync - investigation notes

This document captures the approaches considered, findings from live testing on macOS, and what needs to be built before this feature ships.

## Goal

When the user mutes the Wave mic (via hotkey, physical button, or menu), also mute the microphone inside any active Google Meet call, so the two states stay in sync.

## Testing environment

- macOS 15 (Sequoia)
- Google Chrome (tab-based)
- Google Meet PWA installed at `/Applications/Chrome Apps.localized/Google Meet.app`
  - Runs as process `app_mode_loader`
  - Bundle ID: `com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan`
  - Targetable via AppleScript as `application "Google Meet"`

## Findings by Meet surface

### Chrome tab

AppleScript can execute JavaScript on any Chrome tab:

```applescript
tell application "Google Chrome"
    execute tab i of window w javascript "..."
end tell
```

This works with **no extra permissions**. We can find the Meet tab by URL and click the mic button via JS.

Selector: `button[aria-label*="Turn off microphone"]` / `button[aria-label*="Turn on microphone"]`

The `aria-label` is the public accessibility label for the mic button. The text flips with state, so we match by the label of the action we want to perform, not the current state. This is more stable than internal attributes like `jsname` or `data-*`.

### Google Meet PWA

The PWA runs as `app_mode_loader`. It is **not** a browser tab — it exposes no `execute javascript` AppleScript verb. JS injection does not work.

The only viable approaches are:

**Option A: CGEvent Cmd+D**
Google Meet's official keyboard shortcut for toggling the mic is `Cmd+D`. We can synthesise this event and deliver it directly to the `app_mode_loader` process via the Carbon Event Manager or CGEvent API.

- Requires **Accessibility permission** (`AXIsProcessTrusted`)
- Works regardless of which window is focused (we activate Meet briefly, send the event, then restore focus)

**Option B: AXUIElement click**
Use the macOS Accessibility API to find the mic button element by its AX label and click it programmatically.

- Also requires **Accessibility permission**
- More precise than a keyboard shortcut, less likely to misfire if Meet changes its shortcut

**Decision: Option A (Cmd+D CGEvent)** — simpler to implement, uses Meet's own stable API surface, and the shortcut is documented by Google.

Accessibility permission is requested once with a clear explanation dialog. If the user denies it, the Chrome tab path still works; only PWA sync is skipped.

## Architecture

```
toggleMute()
    |
    +-- HIDMonitor.sendMute()          (always)
    |
    +-- MeetSync.sync(muted:)
            |
            +-- Chrome tab found?  --> JS injection (no permissions)
            |
            +-- Meet PWA running?  --> CGEvent Cmd+D (needs Accessibility)
```

Both paths are attempted independently. If neither Meet surface is running, the call is a no-op.

## Implementation plan

1. **`MeetSync.swift`** (prototype exists):
   - Add PWA detection: check if `app_mode_loader` is running with Meet's bundle ID
   - Add `CGEvent` path for PWA: activate Meet, post `Cmd+D`, restore previous app focus
   - Keep JS injection path for Chrome tabs

2. **`AppDelegate.swift`**:
   - Wire `MeetSync.shared.sync(muted:)` into `toggleMute()`
   - Add "Google Meet sync" toggle in the menu (on by default)
   - On first use of PWA sync, show a one-time dialog explaining why Accessibility is needed

3. **`Info.plist`**:
   - Add `NSAppleEventsUsageDescription` (already needed for Chrome JS injection)
   - Add `NSAccessibilityUsageDescription` for the CGEvent path

## Open questions

- [ ] **Locale**: `aria-label` text ("Turn off microphone") is English. Does Meet localise this string in non-English Chrome installs? If so, we need a locale-independent selector.
- [ ] **Reverse sync**: if the user mutes inside Meet (via button or Cmd+D), the Wave mic LED does not change. Full bidirectional sync is a separate, harder problem — out of scope for this iteration.
- [ ] **Focus disruption**: the PWA path briefly activates the Meet window to deliver Cmd+D. Need to measure if this is noticeable to the user and whether focus can be restored fast enough.
- [ ] **Multiple Meet instances**: what if the user has a Chrome Meet tab AND the PWA open simultaneously? Currently both would be toggled. Decide: first found wins, or all?
- [ ] **Teams / Zoom**: same pattern could apply to other meeting apps. Out of scope for this iteration but worth a follow-up issue.

## Testing plan

### Chrome tab
1. Join a Meet call in Chrome (not PWA)
2. Confirm mic is active (green mic icon in Meet)
3. Press F9 in WaveMute
4. Verify: Wave LED goes red AND Meet mic button mutes
5. Press F9 again
6. Verify: Wave LED goes off AND Meet mic button unmutes

### Meet PWA
1. Join a call via the Meet PWA from the Dock
2. Repeat steps 3-6 above
3. Verify the Accessibility permission prompt appears on first run and is clearly explained
4. After granting permission, verify sync works

### No Meet open
1. Close all Meet tabs and the PWA
2. Toggle mute
3. Verify: Wave mutes normally, no errors or delays
