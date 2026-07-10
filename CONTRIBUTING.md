# Contributing

Thanks for your interest in WaveMute. This document covers the development workflow, conventions, and how releases are cut.

## Getting started

```bash
git clone https://github.com/leo-santanna/mic-mute-utility.git
cd mic-mute-utility
brew install hidapi swiftlint swiftformat shellcheck gitleaks pre-commit
pre-commit install
pre-commit install --hook-type commit-msg
```

## Development workflow

1. Open an issue before starting significant work so we can discuss the approach.
2. Fork the repo and create a branch off `main` using the naming convention below.
3. Make your changes. All commits go through pre-commit hooks automatically.
4. Open a PR targeting `main`. The CI pipeline (lint, build, security) must pass before it can be merged.

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

<optional body>
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`.

GitHub Actions uses these to auto-generate release notes, so clear commit messages directly improve the changelog.

## Local checks

The pre-commit hooks run automatically on `git commit`. To run them manually:

```bash
pre-commit run --all-files
```

To build and verify the app bundle locally:

```bash
bash build.sh
```

## Release process

Releases are driven by git tags. Only maintainers create releases.

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `WaveMute/Info.plist`.
2. Update `CHANGELOG.md` with a summary of changes.
3. Commit and merge to `main` via a PR.
4. Tag the merge commit:

```bash
git tag v1.2.0
git push origin v1.2.0
```

GitHub Actions picks up the tag, builds the app, and publishes a release with auto-generated notes and a downloadable `WaveMute-<version>.zip`.
