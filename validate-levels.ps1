param([string]$Path = "assets/campaign.json")
$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
$oldPath = $env:PATH
try {
    New-Item -ItemType Directory -Force build | Out-Null
    $odinRoot = (& odin root).Trim()
    $env:PATH = (Join-Path $odinRoot "vendor/raylib/windows") + ";" + $env:PATH
    & odin run tools/validate -define:HEADLESS=true -define:RAYLIB_SHARED=true -linker:lld -out:build/validate-campaign.exe -- $Path
    if ($LASTEXITCODE -ne 0) { throw "Campaign validation failed." }
} finally { $env:PATH = $oldPath; Pop-Location }
