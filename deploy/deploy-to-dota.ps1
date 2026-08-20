# Deploy the repo's bots/ folder into the local Dota 2 install.
# Usage: .\deploy-to-dota.ps1 [-DotaPath "D:\Games\Steam\steamapps\common\dota 2 beta"]
param(
    [string]$DotaPath = ""
)
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Find-DotaPath {
    $steam = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { throw "Steam not found in registry; pass -DotaPath" }
    $steam = $steam -replace "/", "\"
    $libs = @($steam)
    $libFile = Join-Path $steam "steamapps\libraryfolders.vdf"
    if (Test-Path $libFile) {
        Get-Content $libFile | ForEach-Object {
            if ($_ -match '"path"\s+"([^"]+)"') { $libs += ($Matches[1] -replace "\\\\", "\") }
        }
    }
    foreach ($lib in $libs) {
        $candidate = Join-Path $lib "steamapps\common\dota 2 beta"
        if (Test-Path $candidate) { return $candidate }
    }
    throw "dota 2 beta not found in any Steam library; pass -DotaPath"
}

if (-not $DotaPath) { $DotaPath = Find-DotaPath }
$target = Join-Path $DotaPath "game\dota\scripts\vscripts\bots"
if ($target -notmatch 'scripts\\vscripts\\bots$') {
    throw "refusing to mirror onto '$target' - not a vscripts\bots folder"
}

Write-Host "repo:   $RepoRoot"
Write-Host "target: $target"
if (Test-Path (Join-Path $RepoRoot ".git")) {
    git -C $RepoRoot pull --ff-only
    if ($LASTEXITCODE -ne 0) { Write-Warning "git pull failed; deploying the files already on disk" }
    $commit = git -C $RepoRoot rev-parse --short HEAD
} else {
    Write-Warning "this folder is not a git clone (ZIP download?) - skipping pull, deploying the files already on disk. Clone with git to get one-click updates."
    $commit = "unknown (not a git clone)"
}
robocopy (Join-Path $RepoRoot "bots") $target /MIR /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed with exit code $LASTEXITCODE - if the target is under Program Files, re-run this script AS ADMINISTRATOR (right-click -> Run as administrator)"
}
# prove the copy actually landed: spot-check a file that only exists in current builds
$marker = Join-Path $target "FretBots\HeroHandicap.lua"
if (-not (Test-Path $marker)) {
    throw "deploy verification FAILED: $marker missing after copy - the game folder was NOT updated"
}
Write-Host "deploy verified: HeroHandicap.lua present in target"
Write-Host "deployed commit $commit"
Write-Host "in-game check: console prints '[IQ] FightIQ lib loaded (build ...)'"
