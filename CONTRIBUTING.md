# Contributing

## Local testing

The shell scripts can be exercised directly (see `README.md`). Resolution
needs no network beyond the official manifest; `install` downloads the
archive + SHA-256 digest from nodejs.org.

```bash
# Resolve only (no side effects)
INPUT_VERSION=lts bash scripts/setup-posix.sh resolve

# Full install into a scratch tool cache
INPUT_VERSION=22.23.2 RUNNER_TOOL_CACHE=/tmp/node-cache \
  bash scripts/setup-posix.sh install

# Assert + emit outputs
INPUT_VERSION=22.23.2 RUNNER_TOOL_CACHE=/tmp/node-cache \
  bash scripts/setup-posix.sh finalize
```

On macOS: `shasum -a 256`, on Linux: `sha256sum`. The script uses `shasum -a 256`
which is available on both.

## Versioning and tags

- The moving `v1` tag points at the latest 1.x commit and is used by consumers
  (`devstroop/setup-node@v1`). Force-push `v1` alongside a release.
- Keep `v1.x.y` tags immutable.
- Update `CHANGELOG.md` with each release.

## CI

Push to `main` triggers the self-test matrix in `.github/workflows/test.yml`
(6 runner/version combos). All must pass before tagging.

## Behavior notes

- The action is a composite script with no Node runtime by design — do not
  migrate it to a JavaScript action.
- Version resolution and the version assertion must stay exact: never fall
  back to an older version silently, and never skip SHA-256 verification
  (see `SECURITY.md`).
- macOS archives are listed as `osx-*` keys in the manifest but named
  `darwin-*` on disk — keep the mapping in `resolve` in sync with the
  official `SHASUMS256.txt` naming.