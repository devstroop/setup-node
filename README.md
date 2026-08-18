# Setup Node

GitHub Action that installs a pinned Node.js runtime from the official
`nodejs.org` archives (SHA-256 verified), exposes it on `PATH`, and exports
`NODE_DIR` for the rest of the job.

Pure bash + Python — no Node runtime, no third-party actions for the setup
itself (only `actions/cache` for the tiered toolchain caching).

## Inputs

| Input       | Default  | Description |
|-------------|----------|-------------|
| `version`   | `lts`    | `lts` / `current` channel, a line like `22` or `22.23` (newest release on that line), or an exact version like `22.23.2` |
| `use-cache` | `true`   | Cache the runtime between runs |
| `cache-key` | ``       | Extra cache key component (recommend `${{ matrix.name }}` in matrices) |

## Outputs

| Output        | Description |
|---------------|-------------|
| `node-version` | Resolved version (e.g. `24.19.0`, no `v` prefix) |
| `node-root`    | Installation directory (contains `bin/node`, or `node.exe` on Windows) |
| `cache-hit`    | Whether the toolchain was restored from cache |

## Usage

```yaml
- uses: devstroop/setup-node@v1
  with:
    version: '22'            # or '22.23.2', 'lts', 'current'
    cache-key: linux-arm64   # recommended in matrices

- run: node --version
- run: npm ci
- run: npm test
```

Version semantics (mirrors `setup-zig` / `setup-flutter`):

- `lts` — newest LTS release (default)
- `current` — newest release overall (may be a non-LTS odd-numbered line)
- `22` / `22.23` — newest release on that line
- `22.23.2` — exact release

The archive filename for the runner's `os`/`arch` is validated against the
release's `files` list in the official manifest before download (note: the
manifest lists macOS archives as `osx-*` while the archives themselves are
named `darwin-*`; the action maps between them).

## Caching

Keyed by exact resolved version:
`setup-node-${{ runner.os }}-${{ runner.arch }}-<version>__<cache-key>`.

No `restore-keys` fallback is used: restoring an older runtime into the
resolved version's directory would fail the version assertion in the finalize
step (and with `version: lts` the resolved version changes over time). Cache
misses add a few seconds (archive is ~50 MB); subsequent runs with the same
version restore instantly.

## Notes

- Windows uses `scripts/setup-windows.ps1` for install; resolution and the
  version assertion still run in Git Bash so behavior is identical across OSes.
- `NODE_DIR` is exported to the environment and `bin` is prepended to `PATH`,
  so `node`, `npm`, `npx`, and `corepack` are available to later steps.
- The bundled npm is used as-is; no separate npm/corepack install step.
- Self-tests live in `.github/workflows/test.yml` (channel / line / exact
  resolution, SHA-256 verification, version assertion, smoke app).

## License

MIT