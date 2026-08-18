#!/usr/bin/env bash
# setup-posix.sh — resolve, install, and assert a pinned Node.js runtime.
# (resolve + finalize also run on Windows in Git Bash.)
#
# Usage:
#   setup-posix.sh resolve    # env: INPUT_VERSION, INPUT_CACHE_KEY
#                             # emits resolved-version, archive-url, sha256,
#                             # install-root, cache-key via $GITHUB_OUTPUT
#   setup-posix.sh install    # env: INSTALL_ROOT, ARCHIVE_URL, SHA256, CACHE_HIT
#                             # downloads + verifies + extracts, appends
#                             # <root>/bin to $GITHUB_PATH
#   setup-posix.sh finalize   # env: INPUT_VERSION, RESOLVED_VERSION, INSTALL_ROOT
#                             # runs node --version, asserts the resolved
#                             # version, exports NODE_DIR, and emits
#                             # node-version/node-root
#
# Version semantics (mirroring setup-flutter's tiering):
#   lts                -> newest LTS release (default)
#   current            -> newest release overall (may be a non-LTS line)
#   22 | 22.23         -> newest release on that line
#   22.23.2            -> exact release
#
# Sources are the official nodejs.org dist manifest and archives; every
# download is verified against the per-release SHASUMS256.txt.

set -euo pipefail

BASE="https://nodejs.org/dist"

TMP_DIR=""
trap '[ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"' EXIT

emit() { # name value
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        echo "$1=$2" >> "$GITHUB_OUTPUT"
    else
        echo "$1=$2"
    fi
}

forward_slashes() { printf '%s' "$1" | sed 's|\\|/|g'; }

fail() {
    echo "error: $*" >&2
    exit 1
}

resolve() {
    local uname_os="${OSTYPE:-$(uname -s)}"
    local platform
    case "$uname_os" in
        darwin*) platform="macos" ;;
        linux*)  platform="linux" ;;
        msys*|mingw*|cygwin*) platform="windows" ;;
        *) fail "unsupported OS: $uname_os" ;;
    esac

    local runner_arch="${RUNNER_ARCH:-}"
    [ -z "$runner_arch" ] && runner_arch="$(uname -m)"
    case "$runner_arch" in
        arm64|aarch64) runner_arch="arm64" ;;
        *) runner_arch="x64" ;;
    esac

    local manifest_file
    manifest_file="$(mktemp)"
    curl -fsSL --retry 3 -o "$manifest_file" "${BASE}/index.json" || {
        rm -f "$manifest_file"
        fail "unable to fetch release manifest: ${BASE}/index.json"
    }

    # Resolve the requested version against the manifest. Note the archive
    # filename naming quirk: the manifest's files list uses "osx-<arch>-tar"
    # keys for macOS while the actual archives are named "darwin-<arch>".
    # The filename is built below from the (validated) platform/arch pair,
    # never from the manifest key directly.
    local out
    out=$(INPUT_VERSION="${INPUT_VERSION:-lts}" PLATFORM="$platform" ARCH="$runner_arch" python3 - "$manifest_file" 2>&1 <<'PYEOF'
import json, os, sys

ver = os.environ["INPUT_VERSION"]
plat = os.environ["PLATFORM"]
arch = os.environ["ARCH"]
m = json.load(open(sys.argv[1]))

def line_key(v):
    try:
        return tuple(int(x) for x in v.lstrip("v").split("."))
    except ValueError:
        return (0, 0, 0)

sel = None
if ver in ("lts", "current"):
    cands = m if ver == "current" else [r for r in m if r.get("lts")]
    if not cands:
        sys.exit(f"channel '{ver}' not present in release manifest")
    sel = cands[0]
else:
    q = ver[1:] if ver.startswith("v") else ver
    if q.count(".") <= 1:
        prefix = f"v{q}."
        cands = [r for r in m if r["version"].startswith(prefix)]
        if not cands:
            sys.exit(f"no release matching '{q}.*' in manifest")
        cands.sort(key=lambda r: line_key(r["version"]))
        sel = cands[-1]
    else:
        want = f"v{q}"
        cands = [r for r in m if r["version"] == want]
        if not cands:
            sys.exit(f"no release with version '{q}' in manifest")
        sel = cands[0]

files = sel.get("files", [])
want_key = {"macos": f"osx-{arch}-tar",
            "linux": f"linux-{arch}",
            "windows": f"win-{arch}-zip"}[plat]
if want_key not in files:
    sys.exit(f"no {plat}/{arch} build for {sel['version']} (available: {', '.join(files)})")

print(sel["version"].lstrip("v"))
PYEOF
) || { [ -n "$out" ] && fail "$out" || fail "version resolution failed"; }
    rm -f "$manifest_file"
    local resolved
    resolved="$(printf '%s' "$out" | tail -n 1)"

    # Archive filename: osx-* manifest keys map to darwin-* archive names.
    local stem
    case "$platform" in
        macos)   stem="darwin-${runner_arch}" ;;
        linux)   stem="linux-${runner_arch}" ;;
        windows) stem="win-${runner_arch}" ;;
    esac
    local filename="node-v${resolved}-${stem}.tar.gz"
    [ "$platform" = "windows" ] && filename="node-v${resolved}-${stem}.zip"
    local archive_url="${BASE}/v${resolved}/${filename}"

    # SHA-256 from the official per-release digest file
    local sha_file
    sha_file="$(mktemp)"
    curl -fsSL --retry 3 -o "$sha_file" "${BASE}/v${resolved}/SHASUMS256.txt" || {
        rm -f "$sha_file"
        fail "unable to fetch SHA-256 digest: ${BASE}/v${resolved}/SHASUMS256.txt"
    }
    local sha
    sha="$(awk -v f="$filename" '$2 == f { print $1 }' "$sha_file" | head -n 1)" || true
    rm -f "$sha_file"
    [ -n "$sha" ] || fail "no SHA-256 digest found for $filename"

    local install_root
    install_root="$(forward_slashes "${RUNNER_TOOL_CACHE:-$HOME/hostedtoolcache}/setup-node/${resolved}")"

    emit "resolved-version" "$resolved"
    emit "archive-url" "$archive_url"
    emit "sha256" "$sha"
    emit "install-root" "$install_root"
    emit "cache-key" "${resolved}${INPUT_CACHE_KEY:+__${INPUT_CACHE_KEY}}"
}

install() {
    local node_bin="${INSTALL_ROOT}/bin"

    if [ "${CACHE_HIT:-false}" = "true" ] && [ -x "$node_bin/node" ]; then
        echo "Node.js restored from cache at ${INSTALL_ROOT}"
    else
        mkdir -p "$INSTALL_ROOT"
        TMP_DIR="$(mktemp -d)"

        local archive="$TMP_DIR/node.archive"
        echo "Downloading $ARCHIVE_URL"
        curl -fL --retry 3 --retry-delay 5 -o "$archive" "$ARCHIVE_URL"

        local got
        got="$(shasum -a 256 "$archive" | awk '{print $1}')"
        if [ "$(printf '%s' "$got" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$SHA256" | tr '[:upper:]' '[:lower:]')" ]; then
            fail "SHA-256 mismatch for $(basename "$ARCHIVE_URL"): got $got, expected $SHA256"
        fi
        echo "SHA-256 verified"

        # Node archives contain a top-level node-vX.Y.Z-<plat>-<arch>/ dir;
        # strip it so the runtime lands directly in INSTALL_ROOT.
        case "$ARCHIVE_URL" in
            *.tar.gz) tar -xzf "$archive" -C "$INSTALL_ROOT" --strip-components=1 ;;
            *)        fail "unsupported archive format: $ARCHIVE_URL" ;;
        esac

        [ -x "$node_bin/node" ] || fail "archive did not contain bin/node at $INSTALL_ROOT"

        echo "Node.js installed at ${INSTALL_ROOT}"
    fi

    # Make node/npm/npx/corepack available to subsequent steps
    echo "$node_bin" >> "$GITHUB_PATH"
    echo "Added $node_bin to PATH"
}

finalize() {
    [ -x "${INSTALL_ROOT}/bin/node" ] || fail "node binary not found at ${INSTALL_ROOT}/bin/node"

    # node --version prints a leading "v"; strip it for the assertion.
    local reported
    reported="$("$INSTALL_ROOT/bin/node" --version 2>&1 | tr -d '\r')"
    echo "node --version: $reported"
    case "$reported" in
        "v${RESOLVED_VERSION}")
            echo "version assertion passed: ${RESOLVED_VERSION}" ;;
        *)
            echo "error: node --version reported: $reported" >&2
            echo "       expected v${RESOLVED_VERSION}" >&2
            exit 1
            ;;
    esac

    # Export for the rest of the job
    if [ -n "${GITHUB_ENV:-}" ]; then
        echo "NODE_DIR=${INSTALL_ROOT}" >> "$GITHUB_ENV"
    fi
    echo "${INSTALL_ROOT}/bin" >> "$GITHUB_PATH"

    emit "node-version" "$RESOLVED_VERSION"
    emit "node-root" "$INSTALL_ROOT"
}

case "${1:-}" in
    resolve)  resolve ;;
    install)  install ;;
    finalize) finalize ;;
    *) fail "usage: $0 {resolve|install|finalize}" ;;
esac