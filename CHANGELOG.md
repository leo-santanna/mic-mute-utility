# Changelog

## [1.2.0] - 2026-07-14

### Added
- About window accessible from the menu bar, showing the app version, a short description, and buttons to open the GitHub repository and Buy Me a Coffee page.

### Fixed
- macOS no longer prompts for Accessibility permission on every app launch. The Meet PWA sync path now uses osascript (a system binary with its own TCC grants) instead of CGEvent, so the app binary requires no Accessibility permission at all.

## [1.1.1] - 2026-07-14

### Fixed
- Wave mic mute and LED stop working after a macOS logout/login cycle without restarting the app. HIDMonitor now automatically detects a stale device handle and reconnects when the USB device is re-enumerated.

## [1.1.0] - 2026-07-10

### Added
- Google Meet sync: muting via hotkey, physical button, or menu bar now also mutes the mic in any active Google Meet call (Chrome tab or PWA)
- Reverse Meet sync: clicking the mute button inside Google Meet syncs back to WaveMute and the Wave mic LED within 500ms
- Beta build indicator: builds not at a release tag show a β badge on the menu bar icon to distinguish from stable releases
- NSAppleEventsUsageDescription and entitlement for Chrome AppleScript access

All notable changes to WaveMute are documented here.

Releases are created by pushing a version tag to `main`. GitHub Actions builds the app, generates release notes from commit messages since the previous tag, and attaches a signed zip to the release automatically.

## [1.0.0] - 2026-07-10

### Added
- Menu bar app with mic.fill / mic.slash.fill SF Symbol icons
- Hardware-level mute via HID Output Report 6 (no CoreAudio involvement)
- LED sync: mic front LED turns red when muted
- Physical button sync: muting via the mic's built-in touch display updates the menu bar icon in real time
- Configurable global hotkey (default F9) with in-app shortcut recorder
- CoreAudio bounce-back guard to prevent "microphone muted by system" warnings in meeting apps
- Launch at login via LaunchAgent
- App icon with navy/indigo gradient
- Self-contained bundle with libhidapi bundled inside (no runtime dependencies)
