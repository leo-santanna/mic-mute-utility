# Release and distribution

This document is the definitive reference for how WaveMute is built, versioned, signed, packaged, and distributed.

---

## Versioning

WaveMute follows [Semantic Versioning](https://semver.org/):

| Change | Bump | Example |
|--------|------|---------|
| New feature, backwards compatible | Minor | `1.1.0` → `1.2.0` |
| Bug fix or improvement | Patch | `1.2.0` → `1.2.1` |
| Breaking change or major rewrite | Major | `1.2.1` → `2.0.0` |

Two fields in `WaveMute/Info.plist` must be updated for every release:

| Key | Role | Example |
|-----|------|---------|
| `CFBundleShortVersionString` | User-facing version string | `1.2.0` |
| `CFBundleVersion` | Build number, increment by 1 each release | `4` |

---

## Build

```bash
bash build.sh
```

`build.sh` performs the following steps:

1. **Detect build type** — beta if HEAD is not at an exact `vX.Y.Z` tag; passes `-D BETA_BUILD` to `swiftc` for non-release builds.
2. **Compile** — all Swift sources in `WaveMute/` into `WaveMute.app/Contents/MacOS/WaveMute`.
3. **Bundle libhidapi** — copies `/opt/homebrew/lib/libhidapi.dylib` into `Contents/Frameworks/`, sets `@rpath` install name, adds rpath to the binary.
4. **Copy resources** — `Info.plist` and `AppIcon.icns`.
5. **Sign** — ad-hoc signs (`codesign --sign -`) dylib, binary, and bundle in dependency order.
6. **Clear quarantine** — `xattr -cr` so the app opens without a right-click prompt on the build machine.

### Prerequisites

```bash
brew install hidapi swiftlint swiftformat shellcheck gitleaks pre-commit
pre-commit install
```

### Build types

| Condition | Type | Badge |
|-----------|------|-------|
| HEAD at exact `vX.Y.Z` tag | Release | None |
| Any other commit | Beta | β in menu bar icon |

---

## Release checklist

Follow these steps in order for every release.

### 1. Bump version

Edit `WaveMute/Info.plist`:
- Increment `CFBundleShortVersionString` per semver rules above
- Increment `CFBundleVersion` by 1

### 2. Update CHANGELOG.md

Add a new section at the top following the existing format:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- ...

### Fixed
- ...

### Changed
- ...
```

### 3. Commit and merge via PR

```bash
git checkout -b chore/release-X.Y.Z
git add WaveMute/Info.plist CHANGELOG.md
git commit -m "chore: release X.Y.Z"
git push -u origin chore/release-X.Y.Z
```

Open a PR, ensure all CI checks pass (lint, build, security), then merge.

### 4. Tag the merge commit

```bash
git checkout main && git pull
git tag vX.Y.Z
git push origin vX.Y.Z
```

### 5. Verify the release

The `release.yml` workflow fires automatically. Within ~5 minutes:

- The release appears at `https://github.com/leo-santanna/mic-mute-utility/releases/tag/vX.Y.Z`
- `WaveMute-X.Y.Z.zip` is attached as a release asset

Download the zip and confirm the app launches correctly before announcing.

---

## CI pipeline

Defined in `.github/workflows/ci.yml`. Runs on every PR and push to `main`.

| Job | What it checks |
|-----|----------------|
| `lint` | SwiftLint (strict), SwiftFormat (lint mode), ShellCheck |
| `build` | Full `build.sh` run + bundle structure verification |
| `security` | Gitleaks full-history secret scan |

All three jobs must pass before a PR can be merged. Branch protection enforces this.

---

## Release pipeline

Defined in `.github/workflows/release.yml`. Triggered by `vX.Y.Z` tag pushes.

Steps:
1. Check out at the tagged commit
2. Install `hidapi` via Homebrew
3. Run `build.sh` (detects tag → release build, no beta flag)
4. Verify bundle structure
5. Package with `ditto -c -k --keepParent WaveMute.app WaveMute-X.Y.Z.zip`
6. Create GitHub Release with auto-generated notes and zip asset

---

## Distribution

### Current: GitHub Releases

Users download `WaveMute-X.Y.Z.zip` from the Releases page. On first launch they must right-click > Open to bypass Gatekeeper (the app is ad-hoc signed, not notarized).

### Future: Apple notarization

Notarization requires:
- Apple Developer Program membership ($99/year)
- A Developer ID Application certificate
- `--options runtime` added to `codesign`
- `xcrun notarytool submit` + `xcrun stapler staple` added to the release pipeline

Once notarized, the app opens normally without the right-click step.

### Future: Homebrew cask

A cask definition in a tap (`leo-santanna/homebrew-wavemute`) would allow:

```bash
brew install --cask wavemute
```

Requirements: public repo, notarized build, cask `.rb` file with `sha256` updated per release. The `sha256` can be computed and committed automatically in the release workflow.

---

## Local beta testing workflow

```bash
# Build beta alongside stable
bash build.sh
cp -r WaveMute.app /Applications/WaveMute\ Beta.app
xattr -cr /Applications/WaveMute\ Beta.app
open /Applications/WaveMute\ Beta.app

# Remove beta when done
pkill -f "WaveMute Beta"
rm -rf /Applications/WaveMute\ Beta.app
```

Beta builds show a `β` badge on the menu bar icon. The stable `/Applications/WaveMute.app` continues running alongside it.

---

## If the release workflow fails

1. Check the failing step in the Actions tab on GitHub.
2. Fix on a branch, merge via PR as normal.
3. Delete and re-push the tag:

```bash
git tag -d vX.Y.Z
git push origin :refs/tags/vX.Y.Z
git pull
git tag vX.Y.Z
git push origin vX.Y.Z
```

Never tag a commit that bypassed the CI pipeline.
