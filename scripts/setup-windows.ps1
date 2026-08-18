# setup-windows.ps1 — install the Node.js archive on Windows.
# (resolve + finalize run in Git Bash on Windows; only the download/extract
# lives here.)
#
# env: RESOLVED_VERSION, INSTALL_ROOT, ARCHIVE_URL, SHA256, CACHE_HIT, GITHUB_PATH
#   INSTALL_ROOT is emitted by setup-posix.sh resolve (forward slashes).

$ErrorActionPreference = "Stop"

$nodeBin = Join-Path $env:INSTALL_ROOT "bin"

if ($env:CACHE_HIT -eq "true" -and (Test-Path (Join-Path $nodeBin "node.exe"))) {
    Write-Host "Node.js restored from cache at $env:INSTALL_ROOT"
} else {
    New-Item -ItemType Directory -Force -Path $env:INSTALL_ROOT | Out-Null

    $archive = Join-Path $env:INSTALL_ROOT "node.archive"
    Write-Host "Downloading $env:ARCHIVE_URL"
    curl.exe -fL --retry 3 --retry-delay 5 -o $archive $env:ARCHIVE_URL
    if ($LASTEXITCODE -ne 0) { throw "download failed: $env:ARCHIVE_URL" }

    $got = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLowerInvariant()
    $want = $env:SHA256.ToLowerInvariant()
    if ($got -ne $want) {
        throw "SHA-256 mismatch for $(Split-Path $env:ARCHIVE_URL -Leaf): got $got, expected $want"
    }
    Write-Host "SHA-256 verified"

    if ($env:ARCHIVE_URL -like "*.zip") {
        # Node archives contain a top-level node-vX.Y.Z-win-<arch>/ dir;
        # move its contents up so the runtime lands directly in INSTALL_ROOT.
        $expanded = Join-Path $env:INSTALL_ROOT "expanded"
        Expand-Archive -Path $archive -DestinationPath $expanded -Force
        $inner = Get-ChildItem -Path $expanded -Directory | Select-Object -First 1
        if (-not $inner) { throw "archive did not contain a node directory" }
        Get-ChildItem -Path $inner.FullName -Force | Move-Item -Destination $env:INSTALL_ROOT -Force
        Remove-Item $expanded -Recurse -Force
        Remove-Item $archive -Force
    } else {
        throw "unsupported archive format: $env:ARCHIVE_URL"
    }

    if (-not (Test-Path (Join-Path $nodeBin "node.exe"))) {
        throw "archive did not contain bin/node.exe at $env:INSTALL_ROOT"
    }
    Write-Host "Node.js installed at $env:INSTALL_ROOT"
}

Add-Content -Path $env:GITHUB_PATH -Value $nodeBin
Write-Host "Added $nodeBin to PATH"