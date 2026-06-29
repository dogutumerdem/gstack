#!/usr/bin/env pwsh
# setup.ps1 — Windows PowerShell installer for gstack
#
# Wraps the bash setup script via Git Bash (ships with Git for Windows).
# Prerequisite checklist, path conversion, and bash invocation all handled here.
#
# Usage:
#   .\setup.ps1                        # interactive, flat skill names (/ship, /qa, etc.)
#   .\setup.ps1 --prefix               # namespaced (/gstack-ship, /gstack-qa, etc.)
#   .\setup.ps1 --host codex           # install for Codex instead of Claude
#   .\setup.ps1 --host auto            # detect and install for all found agents
#   .\setup.ps1 --team                 # enable team / auto-update mode
#   .\setup.ps1 --plan-tune-hooks      # install plan-tune AskUserQuestion hooks
#   .\setup.ps1 --quiet                # suppress informational output
#   .\setup.ps1 --fix-playwright       # only fix a broken Playwright Chromium install
#   .\setup.ps1 --skip-browser         # install skills now, skip Playwright check
#                                      # (run .\setup.ps1 --fix-playwright afterward)
#
# After install, re-run this script after every `git pull` — Windows can't
# use symlinks, so skill files are copied and need to be refreshed manually.

param(
    [string]$Host = "",
    [switch]$Prefix,
    [switch]$NoPrefix,
    [switch]$Team,
    [switch]$NoTeam,
    [switch]$PlanTuneHooks,
    [switch]$NoPlanTuneHooks,
    [switch]$Quiet,
    [switch]$FixPlaywright,
    [switch]$SkipBrowser,
    [switch]$Help
)

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path
    exit 0
}

$ErrorActionPreference = "Stop"
$GSTACK_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Status([string]$msg) {
    if (-not $Quiet) { Write-Host $msg }
}

function Write-Error-Exit([string]$msg) {
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

# ─── 1. Find Git Bash ────────────────────────────────────────────────────────
$BASH_EXE = $null

# Common installation paths for Git for Windows
$BASH_CANDIDATES = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "$env:ProgramFiles\Git\usr\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
    "C:\msys64\usr\bin\bash.exe",
    "C:\msys2\usr\bin\bash.exe"
)

# Also check PATH
$bashInPath = Get-Command bash -ErrorAction SilentlyContinue
if ($bashInPath) {
    $BASH_EXE = $bashInPath.Source
}

if (-not $BASH_EXE) {
    foreach ($candidate in $BASH_CANDIDATES) {
        if (Test-Path $candidate) {
            $BASH_EXE = $candidate
            break
        }
    }
}

if (-not $BASH_EXE) {
    Write-Host ""
    Write-Host "ERROR: Git Bash not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "gstack's skill scripts are bash scripts and require Git Bash to run."
    Write-Host "Install Git for Windows from: https://git-scm.com/download/win"
    Write-Host "  (Choose 'Add Git to PATH' during install for best results)"
    Write-Host ""
    exit 1
}

Write-Status "  bash: $BASH_EXE"

# ─── 2. Check bun ────────────────────────────────────────────────────────────
$bun = Get-Command bun -ErrorAction SilentlyContinue
if (-not $bun) {
    Write-Host ""
    Write-Host "ERROR: bun is not installed." -ForegroundColor Red
    Write-Host ""
    Write-Host "Install bun: https://bun.sh/"
    Write-Host "  Or via PowerShell: irm bun.sh/install.ps1 | iex"
    Write-Host ""
    exit 1
}
$bunVersion = (bun --version 2>&1)
Write-Status "  bun: $bunVersion"

# ─── 3. Check Node.js (required on Windows for Playwright) ───────────────────
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Host ""
    Write-Host "ERROR: Node.js is not installed." -ForegroundColor Red
    Write-Host ""
    Write-Host "Node.js is required on Windows because Bun cannot launch Chromium"
    Write-Host "directly (oven-sh/bun#4253). Install from: https://nodejs.org/"
    Write-Host ""
    exit 1
}
$nodeVersion = (node --version 2>&1)
Write-Status "  node: $nodeVersion"

# ─── 4. Handle --fix-playwright shortcut ─────────────────────────────────────
if ($SkipBrowser) {
    Write-Status ""
    Write-Status "Skipping Playwright check — installing skills directly..."

    $installScript = Join-Path $GSTACK_DIR "bin\gstack-install-skills"
    if (-not (Test-Path $installScript)) {
        Write-Error-Exit "gstack-install-skills helper not found. Please update gstack first."
    }

    & $BASH_EXE --login -c "'$installScript'"
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Error-Exit "gstack-install-skills failed (exit $exitCode)"
    }
    Write-Host ""
    Write-Host "Skills installed." -ForegroundColor Green
    Write-Host "Run '.\setup.ps1 --fix-playwright' once Playwright finishes downloading."
    exit 0
}

if ($FixPlaywright) {
    Write-Status ""
    Write-Status "Fixing Playwright Chromium installation..."

    # Remove stale lock if present
    $lockPath = "$env:LOCALAPPDATA\ms-playwright\__dirlock"
    if (Test-Path $lockPath) {
        Remove-Item $lockPath -Recurse -Force
        Write-Status "  Removed stale Playwright lock"
    }

    # Install chromium via npx from the gstack dir
    Push-Location $GSTACK_DIR
    try {
        & npx playwright install chromium
        if ($LASTEXITCODE -ne 0) {
            Write-Error-Exit "Playwright Chromium install failed (exit $LASTEXITCODE)"
        }
    } finally {
        Pop-Location
    }

    Write-Status ""
    Write-Status "Playwright Chromium fixed. Re-run .\setup.ps1 to complete installation."
    exit 0
}

# ─── 5. Build bash args from PowerShell params ───────────────────────────────
$bashArgs = @()
if ($Host)          { $bashArgs += @("--host", $Host) }
if ($Prefix)        { $bashArgs += "--prefix" }
if ($NoPrefix)      { $bashArgs += "--no-prefix" }
if ($Team)          { $bashArgs += "--team" }
if ($NoTeam)        { $bashArgs += "--no-team" }
if ($PlanTuneHooks) { $bashArgs += "--plan-tune-hooks" }
if ($NoPlanTuneHooks) { $bashArgs += "--no-plan-tune-hooks" }
if ($Quiet)         { $bashArgs += "--quiet" }

# ─── 6. Convert gstack directory to a POSIX path for Git Bash ────────────────
# Git Bash uses /c/Users/... style paths, not C:\Users\...
# Convert: replace backslashes, handle drive letter (C: → /c)
$posixDir = $GSTACK_DIR -replace '\\', '/'
if ($posixDir -match '^([A-Za-z]):(.*)') {
    $drive = $Matches[1].ToLower()
    $rest = $Matches[2]
    $posixDir = "/$drive$rest"
}

# ─── 7. Remove stale Playwright lock before running setup ────────────────────
$lockPath = "$env:LOCALAPPDATA\ms-playwright\__dirlock"
if (Test-Path $lockPath) {
    Write-Status "  Removing stale Playwright lock..."
    Remove-Item $lockPath -Recurse -Force
}

# ─── 8. Run the bash setup script ────────────────────────────────────────────
Write-Status ""
Write-Status "Running gstack setup..."
Write-Status "  gstack dir: $GSTACK_DIR"
Write-Status ""

$setupScript = Join-Path $GSTACK_DIR "setup"

# Build the bash command: cd into the posix path, run setup
$bashCmd = "cd '$posixDir' && bash setup $($bashArgs -join ' ')"

& $BASH_EXE --login -c $bashCmd
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "Setup failed (exit $($proc.ExitCode))." -ForegroundColor Red
    Write-Host ""
    Write-Host "Common fixes:"
    Write-Host "  Playwright lock:  .\setup.ps1 --fix-playwright"
    Write-Host "  Skip browser:     .\setup.ps1 --skip-browser  (installs skills now, fix browser later)"
    Write-Host "  Force rebuild:    Remove-Item browse\dist -Recurse -Force; .\setup.ps1"
    Write-Host ""
    exit $exitCode
}

Write-Host ""
Write-Host "gstack installed successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Next: restart Claude Code (Ctrl+R or restart the app) to pick up the new skills."
Write-Host "Then type /ship, /qa, /review etc. to start using gstack."
Write-Host ""
Write-Host "Note: re-run .\setup.ps1 after every 'git pull' — Windows uses file"
Write-Host "copies (not symlinks), so skills won't auto-update."
