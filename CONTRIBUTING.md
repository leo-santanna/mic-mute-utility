# Contributing

Thanks for your interest in WaveMute. This document covers the development workflow, commit conventions, local tooling setup, and the full release process.

---

## Table of contents

- [Getting started](#getting-started)
- [Development workflow](#development-workflow)
- [Local checks](#local-checks)
- [Release process](#release-process)

---

## Getting started

```bash
git clone https://github.com/leo-santanna/mic-mute-utility.git
cd mic-mute-utility
brew install hidapi swiftlint swiftformat shellcheck gitleaks pre-commit
pre-commit install
pre-commit install --hook-type commit-msg
```

The last two commands install the git hooks. From this point on, every `git commit` automatically runs the full suite of checks (formatting, linting, secret scanning) before the commit is created.

---

## Development workflow

1. Open an issue before starting significant work so we can align on the approach.
2. Fork the repo and create a branch off `main` using the naming convention below.
3. Make your changes. Commits go through pre-commit hooks automatically.
4. Open a PR targeting `main`. All three CI jobs (lint, build, security) must pass and the branch must be up to date before it can be merged.

### Branch naming

| Type | Pattern | Example |
|------|---------|---------|
| Feature | `feat/<short-description>` | `feat/device-reconnect` |
| Bug fix | `fix/<short-description>` | `fix/led-flicker` |
| Docs | `docs/<short-description>` | `docs/update-readme` |
| Chore | `chore/<short-description>` | `chore/bump-swiftlint` |

### Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>

<optional body explaining why, not what>
```

**Types:** `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`

GitHub Actions generates release notes from commit messages since the previous tag, so a clear commit message is a direct contribution to the changelog.

Good examples:

```
feat(monitor): sync icon when mic is muted via physical button
fix(hid): suppress LED bounce-back after Report 6 write
chore(ci): update SwiftLint to 0.56.0
```

---

## Local checks

Pre-commit hooks run automatically on every `git commit`. To run the full suite manually at any time:

```bash
pre-commit run --all-files
```

Individual tools can also be run directly:

```bash
swiftlint lint              # Swift style and correctness
swiftformat --lint WaveMute/  # Swift formatting (lint only, no changes)
swiftformat WaveMute/         # Swift formatting (apply changes)
shellcheck build.sh         # Shell script analysis
gitleaks detect --source .  # Secret scanning
```

To build and verify the app bundle locally:

```bash
bash build.sh
# Produces WaveMute.app in the project root.
# Open it directly or copy to /Applications.
```

---

## Release process

Releases are created by maintainers only. The process is driven by git tags: pushing a tag of the form `vX.Y.Z` to the repo triggers the `release.yml` GitHub Actions workflow, which builds the app, packages it, and publishes a GitHub Release automatically.

### Versioning

WaveMute follows [Semantic Versioning](https://semver.org/):

| Change | Version bump | Example |
|--------|-------------|---------|
| New feature, backwards compatible | Minor | `1.0.0` -> `1.1.0` |
| Bug fix or improvement | Patch | `1.1.0` -> `1.1.1` |
| Breaking change or major rewrite | Major | `1.1.1` -> `2.0.0` |

### Step-by-step

**1. Update the version in the app bundle**

Edit `WaveMute/Info.plist` and update both version fields:

```xml
<key>CFBundleShortVersionString</key>
<string>1.1.0</string>
<key>CFBundleVersion</key>
<string>2</string>
```

`CFBundleShortVersionString` is the user-facing version (shown in Finder). `CFBundleVersion` is the build number; increment it by one each release.

**2. Update CHANGELOG.md**

Add a new section at the top of `CHANGELOG.md` following the existing format:

```markdown
## [1.1.0] - YYYY-MM-DD

### Added
- ...

### Fixed
- ...

### Changed
- ...
```

**3. Commit and merge to main via a PR**

```bash
git checkout -b chore/release-1.1.0
git add WaveMute/Info.plist CHANGELOG.md
git commit -m "chore: release 1.1.0"
git push origin chore/release-1.1.0
# Open a PR, get CI green, merge.
```

**4. Tag the merge commit**

After the PR is merged, pull the latest `main` and tag it:

```bash
git checkout main
git pull
git tag v1.1.0
git push origin v1.1.0
```

That is the only step needed to trigger the release. GitHub Actions does the rest.

### What happens automatically

The `release.yml` workflow runs on every `v*.*.*` tag push and performs the following steps:

1. Checks out the repo at the tagged commit
2. Installs `hidapi` via Homebrew
3. Runs `build.sh` to compile and sign the app bundle
4. Verifies the bundle structure (binary, dylib, icon, plist all present)
5. Packages `WaveMute.app` into `WaveMute-<version>.zip` using `ditto` (preserves macOS extended attributes and code signatures)
6. Creates a GitHub Release named `WaveMute <version>` with:
   - Auto-generated release notes from commit messages since the previous tag
   - The zip file attached as a downloadable asset

The resulting release is immediately available at:
`https://github.com/leo-santanna/mic-mute-utility/releases/tag/v<version>`

### Verifying a release

After the workflow completes (typically under 5 minutes), verify:

- The release page exists with the correct tag and title
- `WaveMute-<version>.zip` is listed as a release asset
- The zip downloads and the app launches correctly:

```bash
cd ~/Downloads
unzip WaveMute-1.1.0.zip
xattr -cr WaveMute.app   # clear Gatekeeper quarantine
open WaveMute.app
```

### If the release workflow fails

1. Check the failing step in the Actions tab on GitHub.
2. Fix the issue on a branch and merge via PR as normal.
3. Delete the tag and re-push it once the fix is on `main`:

```bash
# Delete the tag locally and remotely
git tag -d v1.1.0
git push origin :refs/tags/v1.1.0

# Re-tag the current main
git pull
git tag v1.1.0
git push origin v1.1.0
```

Never push a tag to a commit that hasn't been through the normal PR and CI process.
