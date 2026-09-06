# CI-only diagnostic sampler for the July staged-updater handoff stall.
#
# Runs on the GitHub Actions Windows runner only; never on a user workstation.
# Captures a bounded, secret-free snapshot of the update handoff state:
#   - processes whose executable or command line references the staged
#     hermes-setup.exe (or anything under the e2e hermes-home), plus their
#     full descendant tree: pid, ppid, exe path, sanitized command line,
#     CPU seconds, working set
#   - the update-in-progress marker file (pid + timestamp, non-secret)
#   - git HEAD + `git status --porcelain` file NAMES only (no diffs)
#   - update log filenames/sizes (no contents)
#
# Everything prints to stdout so the parent job log carries the snapshot.
# Usage: powershell -File july-handoff-diagnostics.ps1 -WorkRoot <dir> [-Label handoff|timeout|finally]

param(
    [Parameter(Mandatory = $true)][string]$WorkRoot,
    [string]$Label = "sample"
)

$ErrorActionPreference = "SilentlyContinue"
if ($env:GITHUB_ACTIONS -ne "true") { throw "handoff diagnostics are restricted to disposable CI runners" }

function Write-Section([string]$Name) {
    Write-Output ""
    Write-Output "=== july-handoff-diagnostics [$Label] $Name ==="
}

if (-not (Test-Path $WorkRoot)) {
    Write-Output "=== july-handoff-diagnostics [$Label] WorkRoot not found: $WorkRoot ==="
    exit 0
}
$WorkRoot = (Resolve-Path $WorkRoot).Path

# Flags whose VALUE is redacted from command lines. Names only are kept.
$SensitiveFlags = @("--token", "--key", "--api-key", "--password", "--secret", "-t", "--auth")

function Format-Cmdline([string]$ExePath, [string]$Cmdline) {
    # Tokenize on whitespace, redact the value that follows a sensitive flag,
    # and redact anything that looks like an embedded secret assignment.
    if ([string]::IsNullOrWhiteSpace($Cmdline)) { return "<no cmdline>" }
    $parts = @($Cmdline -split '\s+')
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $p = $parts[$i]
        if ($SensitiveFlags -contains $p.ToLower()) {
            $out.Add($p)
            if ($i + 1 -lt $parts.Count) { $out.Add("<redacted>"); $i++ }
        }
        elseif ($p -match '(?i)(token|secret|password|api[_-]?key)\s*=') {
            $out.Add(($p -replace '=.*$', '=<redacted>'))
        }
        else { $out.Add($p) }
    }
    return ($out -join " ")
}

Write-Section "meta"
Write-Output ("utc={0} workroot={1}" -f (Get-Date).ToUniversalTime().ToString("o"), $WorkRoot)

Write-Section "processes"
$procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
if ($procs.Count -eq 0) {
    Write-Output "Get-CimInstance returned nothing"
}
$rootPids = @{}
foreach ($p in $procs) {
    $exe = [string]$p.ExecutablePath
    $cmd = [string]$p.CommandLine
    $ref = ($exe -like "$WorkRoot\*") -or ($cmd -like "*$WorkRoot\*")
    if ($ref) { $rootPids[[uint32]$p.ProcessId] = $true }
}
# Expand descendants transitively (both directions of interest: children of
# the staged updater and children of its hermes update child).
$changed = $true
while ($changed) {
    $changed = $false
    foreach ($p in $procs) {
        $pp = [uint32]$p.ParentProcessId
        $cp = [uint32]$p.ProcessId
        if (-not $rootPids.ContainsKey($cp) -and $rootPids.ContainsKey($pp)) {
            $rootPids[$cp] = $true
            $changed = $true
        }
    }
}
if ($rootPids.Count -eq 0) {
    Write-Output "no hermes/staged-updater processes alive"
}
foreach ($p in $procs | Sort-Object ProcessId) {
    $cp = [uint32]$p.ProcessId
    if (-not $rootPids.ContainsKey($cp)) { continue }
    $cpu = "-"
    $ws = "-"
    try {
        $raw = Get-Process -Id $cp -ErrorAction SilentlyContinue
        if ($raw) {
            $cpu = [math]::Round($raw.TotalProcessorTime.TotalSeconds, 1)
            $ws  = [math]::Round($raw.WorkingSet64 / 1MB, 1)
        }
    } catch {}
    $marker = ""
    if ($rootPids.ContainsKey([uint32]$p.ParentProcessId)) { $marker = "child-of=$($p.ParentProcessId)" }
    elseif ([uint32]$p.ParentProcessId -ne 0) { $marker = "root(parent=$($p.ParentProcessId))" }
    Write-Output ("pid={0} {1} cpu_s={2} ws_mb={3} exe={4}" -f $cp, $marker, $cpu, $ws, $p.ExecutablePath)
    Write-Output ("  cmd: {0}" -f (Format-Cmdline $p.ExecutablePath $p.CommandLine))
}

Write-Section "update-in-progress-marker"
$markerPath = Join-Path $WorkRoot "hermes-home\hermes-agent\.hermes-update-in-progress"
if (-not (Test-Path $markerPath)) {
    # Common alternate layout: marker lives directly under hermes-home.
    $alt = Join-Path $WorkRoot "hermes-home\.hermes-update-in-progress"
    if (Test-Path $alt) { $markerPath = $alt } else { $markerPath = $null }
}
if ($markerPath -and (Test-Path $markerPath)) {
    $fi = Get-Item $markerPath
    Write-Output ("marker={0} size={1} mtime={2}" -f $fi.FullName, $fi.Length, $fi.LastWriteTimeUtc.ToString("o"))
    # Contents are "pid\nstarted_at" — non-secret by contract.
    Write-Output ("marker-contents: {0}" -f ((Get-Content $markerPath -Raw) -replace "`r?`n", " / ").Trim())
} else {
    Write-Output "no update-in-progress marker found"
}

Write-Section "git"
$repo = Join-Path $WorkRoot "hermes-home\hermes-agent"
if (Test-Path (Join-Path $repo ".git")) {
    $head = & git -C $repo rev-parse HEAD 2>$null
    $branch = & git -C $repo rev-parse --abbrev-ref HEAD 2>$null
    Write-Output ("head={0} branch={1}" -f $head, $branch)
    # Names only: no diff content, no remote URLs, no stash payloads.
    $st = & git -C $repo status --porcelain 2>$null
    if ($st) { $st | ForEach-Object { Write-Output ("status: {0}" -f $_) } }
    else { Write-Output "status: clean" }
    $last = & git -C $repo log -1 --format="%h %ad %s" --date=short 2>$null
    Write-Output ("last-commit: {0}" -f $last)
} else {
    Write-Output "no .git under $repo"
}

Write-Section "logs"
foreach ($dir in @(
    (Join-Path $WorkRoot "hermes-home\hermes-agent\logs"),
    (Join-Path $WorkRoot "hermes-home\logs"))) {
    if (Test-Path $dir) {
        Get-ChildItem $dir -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 15 |
            ForEach-Object {
                Write-Output ("{0} size={1} mtime={2}" -f $_.FullName, $_.Length, $_.LastWriteTimeUtc.ToString("o"))
            }
    }
}
Write-Output ""
Write-Output "=== july-handoff-diagnostics [$Label] done ==="
exit 0
