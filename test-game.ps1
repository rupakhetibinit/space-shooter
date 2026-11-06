$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
$oldPath = $env:PATH
try {
    New-Item -ItemType Directory -Force build | Out-Null
    # Use raylib's shared CRT build to match Odin's Windows test runner.
    $odinRoot = (& odin root).Trim()
    $env:PATH = (Join-Path $odinRoot "vendor/raylib/windows") + ";" + $env:PATH
    & odin test tests -define:HEADLESS=true -define:RAYLIB_SHARED=true -linker:lld -out:build/gameplay-tests.exe
    if ($LASTEXITCODE -ne 0) { throw "Gameplay tests failed." }
} finally { $env:PATH = $oldPath; Pop-Location }
