# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added

- **Initial release** — composite action installing a pinned Node.js runtime
  from the official `nodejs.org` archives:
  - version semantics: `lts`/`current` channels, lines (`22`, `22.23`),
    exact versions (`22.23.2`)
  - SHA-256 verification of every download against the official per-release
    `SHASUMS256.txt`
  - archive selection validated against the release manifest's `files` list
    (including the `osx-*` → `darwin-*` naming mapping)
  - toolchain caching keyed by exact resolved version (no `restore-keys`
    fallback — a stale-restore hit would fail the version assertion)
  - `NODE_DIR` env export and `PATH` setup for later steps
  - outputs: `node-version`, `node-root`, `cache-hit`
  - Windows install via PowerShell; resolution + assertion in shared bash
  - self-test workflow: channel/line/exact resolution, SHA-256 verification,
    version assertion, smoke app across Linux/macOS/Windows