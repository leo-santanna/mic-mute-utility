# ADR-005: Detect beta builds via git tag and compile-time flag

**Date:** 2026-07-10
**Status:** Accepted

## Context

During active development, the app is rebuilt and deployed frequently. It was useful to visually distinguish a development build from the stable released version, especially when both could be installed simultaneously (as `/Applications/WaveMute.app` and `/Applications/WaveMute Beta.app`).

## Decision

`build.sh` determines the build type at compile time:

- In CI: beta if `GITHUB_REF` is not `refs/tags/v*`
- Locally: beta if `git describe --exact-match --tags --match "v*.*.*" HEAD` fails

When beta, `swiftc` receives `-D BETA_BUILD`. `MenuBarIcons.swift` checks `#if BETA_BUILD` and composites a small `β` character in the bottom-right corner of the menu bar icon. The badge colour adapts to the mute state (accent colour when unmuted, white when muted). The composite image uses `isTemplate = true` for the unmuted state so macOS adapts it to dark/light menu bar backgrounds.

Release builds are completely unaffected — the flag is absent and no badge code runs.

## Consequences

- Beta builds are immediately recognisable in the menu bar without requiring a separate app name or version check.
- The beta app can be installed alongside the stable app under a different name (`WaveMute Beta.app`) during development and removed when work is complete.
- Lightweight git tags (not annotated) require `--tags` in `git describe`. Without this flag, the detection fails and all local builds are incorrectly treated as beta.
