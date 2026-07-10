# Changelog

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
