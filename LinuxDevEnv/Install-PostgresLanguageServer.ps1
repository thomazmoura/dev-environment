#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Installs everything needed for the Postgres Language Server VS Code extension to work on this host.

.DESCRIPTION
    The extension (Marketplace id: Supabase.postgrestools, display name "postgres-language-server")
    resolves its server binary from, in order: an explicit `postgres-language-server.bin` setting,
    a local node_modules install, the system PATH, or an auto-download. This script installs the
    server as an npm global package so the `postgres-language-server` binary lands on PATH and the
    extension auto-detects it, then installs the VS Code extension itself via the `code` CLI.

    The npm package uses the "wrapper + per-platform optional packages" pattern. `npm i -g` does NOT
    install a top-level package's optionalDependencies, and the platform package tags its libc as
    "gnu" (which npm reports as "glibc" and rejects), so this script installs the matching platform
    binary explicitly with --force after the wrapper.

.PARAMETER ForceReinstall
    Reinstall the npm package and the VS Code extension even if they are already present.

.PARAMETER SampleConfigDestination
    Optional directory to copy the sample `postgres-language-server.jsonc` into (only if that
    directory does not already contain one). When omitted, the script just reports where the
    template lives.
#>
param(
  [switch] $ForceReinstall,
  [string] $SampleConfigDestination
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sampleConfig = Join-Path $scriptDir "postgres-language-server.sample.jsonc"

# Make node available (the host manages node through nvs, same as Setup-NeoVimLSP.ps1).
if (Test-Path "$HOME/.nvs/nvs.ps1") {
  Write-Host "->> Selecting LTS node via nvs" -ForegroundColor Cyan
  & "$HOME/.nvs/nvs.ps1" use lts
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  Write-Error "npm was not found on PATH. Install node first (see modules/node/Setup-NVS.ps1)."
  exit 1
}

# Resolve the platform-specific package suffix matching this host.
function Get-PlatformPackageSuffix {
  $machine = (uname -m).Trim()
  switch ($machine) {
    { $_ -in @("x86_64", "amd64") } { $arch = "x86_64" }
    { $_ -in @("aarch64", "arm64") } { $arch = "aarch64" }
    default { Write-Error "Unsupported CPU architecture: $machine"; exit 1 }
  }

  if ($IsMacOS) { return "$arch-apple-darwin" }
  if ($IsWindows) { return "$arch-windows-msvc" }

  # Linux: distinguish musl (Alpine) from glibc (Debian/Ubuntu/etc.).
  $libc = "gnu"
  if ((Test-Path "/etc/alpine-release") -or ((& ldd --version 2>&1 | Out-String) -match "musl")) {
    $libc = "musl"
  }
  return "$arch-linux-$libc"
}

# 1. Install the language server binary via npm global.
$serverInstalled = [bool](Get-Command postgres-language-server -ErrorAction SilentlyContinue)
if ($serverInstalled -and -not $ForceReinstall) {
  Write-Host "->> postgres-language-server already on PATH; skipping npm install (use -ForceReinstall to override)" -ForegroundColor Yellow
}
else {
  Write-Host "->> Installing @postgres-language-server/cli (global)" -ForegroundColor Cyan
  npm install --global '@postgres-language-server/cli@latest'
  if ($LASTEXITCODE -ne 0) {
    Write-Error "npm install of @postgres-language-server/cli failed"
    exit 1
  }

  # npm does not install a top-level package's optionalDependencies, so the wrapper's platform
  # binary sibling is missing. Install it explicitly, pinned to the wrapper's version, with
  # --force to bypass npm's libc gate (the package tags libc "gnu" but npm reports "glibc").
  $version = (npm view '@postgres-language-server/cli' version).Trim()
  $suffix = Get-PlatformPackageSuffix
  $platformPackage = "@postgres-language-server/cli-$suffix@$version"
  Write-Host "->> Installing platform binary $platformPackage (global, --force)" -ForegroundColor Cyan
  npm install --global --force $platformPackage
  if ($LASTEXITCODE -ne 0) {
    Write-Error "npm install of $platformPackage failed"
    exit 1
  }
}

Write-Host "->> Verifying binary" -ForegroundColor Cyan
postgres-language-server --version
if ($LASTEXITCODE -ne 0) {
  Write-Error "postgres-language-server is not runnable after install"
  exit 1
}

# 2. Install the VS Code extension (non-fatal if the `code` CLI is unavailable).
if (Get-Command code -ErrorAction SilentlyContinue) {
  $extArgs = @("--install-extension", "Supabase.postgrestools")
  if ($ForceReinstall) { $extArgs += "--force" }
  Write-Host "->> Installing VS Code extension Supabase.postgrestools" -ForegroundColor Cyan
  code @extArgs
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Failed to install the VS Code extension; install it manually from the Marketplace (Supabase.postgrestools)."
  }
}
else {
  Write-Warning "The 'code' CLI was not found; skipping extension install. Install VS Code first (see LinuxHost/code-setup.sh), then run: code --install-extension Supabase.postgrestools"
}

# 3. Sample config.
if ($SampleConfigDestination) {
  $target = Join-Path $SampleConfigDestination "postgres-language-server.jsonc"
  if (Test-Path $target) {
    Write-Host "->> $target already exists; leaving it untouched" -ForegroundColor Yellow
  }
  else {
    New-Item -ItemType Directory -Path $SampleConfigDestination -Force | Out-Null
    Copy-Item $sampleConfig $target
    Write-Host "->> Copied sample config to $target" -ForegroundColor Green
  }
}
else {
  Write-Host "->> Sample config template available at: $sampleConfig" -ForegroundColor Cyan
  Write-Host "    Copy it to a project root as 'postgres-language-server.jsonc' to customize." -ForegroundColor Cyan
}

Write-Host "`nPostgres Language Server setup complete." -ForegroundColor Green
Write-Host "Add a 'db' section to the project's postgres-language-server.jsonc to enable autocompletion and type checking." -ForegroundColor Yellow
