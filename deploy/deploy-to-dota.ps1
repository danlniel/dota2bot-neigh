# Deploy the repo's bots/ folder into the local Dota 2 install.
# Usage: .\deploy-to-dota.ps1 [-DotaPath "D:\Games\Steam\steamapps\common\dota 2 beta"] [-ApiKey "<key>"]
param(
    [string]$DotaPath = "",
    [string]$ApiKey = ""
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

# ML server API key. Never put it in general.lua by hand: the game copy is
# overwritten by the mirror below, and an edited repo copy makes the next
# `git pull` fail (= silently stale deploy). It lives in
# deploy\ml_api_key.txt (gitignored), asked for once, and is injected into
# the DEPLOYED general.lua after every copy.
$keyFile = Join-Path $PSScriptRoot "ml_api_key.txt"
if ($ApiKey) {
    Set-Content -Path $keyFile -Value $ApiKey.Trim() -NoNewline
} elseif (Test-Path $keyFile) {
    $ApiKey = "$(Get-Content -Path $keyFile -Raw)".Trim()  # empty file -> ""
} else {
    $ApiKey = "$(Read-Host 'ML server API key (Enter to skip - adaptive difficulty stays off)')".Trim()
    if ($ApiKey) { Set-Content -Path $keyFile -Value $ApiKey -NoNewline }
}
$ApiKey = $ApiKey.Trim()
if ($ApiKey -and $ApiKey -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "API key in $keyFile has unexpected characters - fix or delete that file and re-run"
}
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

$generalLua = Join-Path $target "Customize\general.lua"
if ($ApiKey) {
    $content = [System.IO.File]::ReadAllText($generalLua)
    $keyPattern = [regex]"Api_Key\s*=\s*'[^']*'"
    if (-not $keyPattern.IsMatch($content)) { throw "Api_Key line not found in $generalLua - key NOT injected" }
    $content = $keyPattern.Replace($content, "Api_Key = '$ApiKey'", 1)
    [System.IO.File]::WriteAllText($generalLua, $content)  # UTF-8, no BOM
    Write-Host "ML API key injected into the deployed general.lua"
} else {
    Write-Warning "no ML API key - the server will answer 401 and adaptive difficulty stays off (re-run with -ApiKey <key>)"
}
# a full settings copy here REPLACES the deployed general.lua (custom_loader
# tries it first) - an old copy hides every new setting and the injected key
$override = Join-Path $DotaPath "game\dota\scripts\vscripts\game\Customize\general.lua"
if (Test-Path $override) {
    Write-Warning "$override exists and OVERRIDES the deployed settings (including the API key). Rename or delete it unless you maintain it on purpose."
}
Write-Host "deployed commit $commit"
Write-Host "in-game check: console prints '[IQ] FightIQ lib loaded (build ...)'"
