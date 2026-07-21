# CLAUDE.md

This file is the entry point for any Claude session working on this repository. Read it completely before doing anything else.

---

## What this project is

WaveMute is a macOS menu bar utility that gives the Insta360 Wave USB microphone a global mute hotkey. It mutes the mic at the hardware level via HID, syncs the front LED, and has bidirectional integration with Google Meet.

Current stable release: **v1.2.0**
Repository: https://github.com/leo-santanna/mic-mute-utility

---

## Read these before writing any code

| Document | When to read |
|----------|-------------|
| [`docs/architecture.md`](docs/architecture.md) | Always. Component map, data flows, key constraints. |
| [`docs/adr/`](docs/adr/) | Before any decision that touches a mechanism already decided. Check if an ADR covers it. |
| [`docs/release-and-distribution.md`](docs/release-and-distribution.md) | Before cutting a release or touching `build.sh` or the CI workflows. |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Before opening PRs, branching, or writing commits. |
| [`CHANGELOG.md`](CHANGELOG.md) | Add an entry under `[Unreleased]` for every user-visible change. |

---

## How to work on this project

### Starting a new feature or fix

1. Read `docs/architecture.md` to understand the component affected.
2. Check `docs/adr/` for any existing decision that constrains the approach.
3. Create a branch: `feat/<description>` or `fix/<description>`.
4. Make changes. Run `pre-commit run --all-files` before pushing.
5. If you made a significant technical decision, write a new ADR in `docs/adr/` using `000-template.md`. Number it sequentially.
6. Update `CHANGELOG.md` under `[Unreleased]`.
7. Open a PR. All three CI jobs (lint, build, security) must pass before merge.

### Cutting a release

Follow the checklist in `docs/release-and-distribution.md` exactly. The short version:

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `WaveMute/Info.plist`.
2. Move `[Unreleased]` entries in `CHANGELOG.md` to a new `[X.Y.Z] - YYYY-MM-DD` section.
3. Commit as `chore: release X.Y.Z`, merge via PR.
4. `git tag vX.Y.Z && git push origin vX.Y.Z` — the release workflow fires automatically.

### Testing locally

```bash
brew install hidapi   # first time only
bash build.sh         # builds WaveMute.app in the project root
```

For a beta build alongside the stable app:

```bash
bash build.sh
cp -r WaveMute.app /Applications/WaveMute\ Beta.app
xattr -cr /Applications/WaveMute\ Beta.app
open /Applications/WaveMute\ Beta.app
```

Beta builds show a `β` badge on the menu bar icon. Remove when done:

```bash
pkill -f "WaveMute Beta" && rm -rf /Applications/WaveMute\ Beta.app
```

---

## Commit and PR rules

- No `Co-Authored-By: Claude` trailers in commit messages.
- No Claude attribution in PR descriptions.
- All commits go under the user's own GitHub account.
- Follow [Conventional Commits](https://www.conventionalcommits.org/): `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`.
- No direct pushes to `main` — all changes via PR.

---

## Key constraints (do not violate without an ADR)

- **Never set `kAudioDevicePropertyMute` to `1` intentionally.** Only reset it to `0` in the bounce-back guard. See ADR-002.
- **Never use `NSAppleScript` or `CGEvent` from the app binary.** Use `osascript` subprocess instead. See ADR-004.
- **Never embed Accessibility or Apple Events entitlements.** The osascript approach makes them unnecessary. See ADR-004.
- **HID device is held open exclusively.** The official Wave Controller app cannot run at the same time as WaveMute without conflict.
- **`libhidapi` is loaded via `dlopen`, not linked.** Do not add it as a hard link dependency.

---

## Project structure

```
WaveMute/               Swift source files
docs/
  architecture.md       component map and data flows
  release-and-distribution.md
  adr/                  Architecture Decision Records
  assets/               images used in README
  google-meet-sync-investigation.md
  discord-announcement.md
  reddit-macapps-post.md
.github/
  workflows/
    ci.yml              lint + build + security on every PR
    release.yml         builds and publishes on vX.Y.Z tag push
  FUNDING.yml           Buy Me a Coffee link
build.sh                one-step build + bundle + sign
make_icon.swift         regenerates AppIcon.icns
icon.iconset/           source PNGs for the icon
CHANGELOG.md            per-release notes
CONTRIBUTING.md         dev workflow, ADR table, release process
CLAUDE.md               this file
```

---

## Linting and formatting

```bash
pre-commit run --all-files   # run all hooks

swiftlint lint               # style and correctness
swiftformat --lint WaveMute/ # formatting check (no changes)
swiftformat WaveMute/        # apply formatting
shellcheck build.sh          # shell script analysis
```

SwiftFormat is configured to run with `--swiftversion 5.9`. `make_icon.swift` is excluded from SwiftLint (it is a standalone build utility, not app source).

---

## When to write an ADR

Write an ADR in `docs/adr/` whenever you:

- Choose one IPC/API mechanism over alternatives (e.g. osascript vs CGEvent)
- Work around a platform quirk that would need re-explaining later
- Accept a trade-off with long-term consequences
- Override or extend an existing decision

Use `docs/adr/000-template.md`. Number sequentially from the last existing ADR.
