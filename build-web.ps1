param([string]$Emsdk = $env:EMSDK, [string]$Output = "build/web", [switch]$QA)
$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
try {
    & (Join-Path $PSScriptRoot "validate-levels.ps1")
    $odinRoot = (& odin root).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not find Odin." }
    $emcc = Get-Command emcc -ErrorAction SilentlyContinue
    if (!$emcc -and $Emsdk) {
        $emccPath = Join-Path $Emsdk "upstream/emscripten/emcc.bat"
        if (Test-Path -LiteralPath $emccPath) { $emcc = $emccPath }
    }
    if (!$emcc) { throw "Emscripten not found. Activate emsdk_env.bat, set EMSDK, or use -Emsdk <sdk-folder>. See README.md." }
    if ($emcc -is [System.Management.Automation.CommandInfo]) { $emcc = $emcc.Source }
    New-Item -ItemType Directory -Force $Output | Out-Null
    & odin build . "-define:WEB_QA=$($QA.IsPresent.ToString().ToLowerInvariant())" -target:js_wasm32 -build-mode:obj -o:speed -define:RAYLIB_WASM_LIB=env.o "-out:$Output/game.o"
    if ($LASTEXITCODE -ne 0) { throw "Odin web compilation failed." }
    Copy-Item (Join-Path $odinRoot "core/sys/wasm/js/odin.js") $Output
    & $emcc "$Output/game.o" (Join-Path $odinRoot "vendor/raylib/wasm/libraylib.web.a") -o "$Output/index.html" -O2 --no-entry -sUSE_GLFW=3 -sWASM_BIGINT=1 -sALLOW_MEMORY_GROWTH=1 -sASSERTIONS=1 -sSTACK_SIZE=1048576 '-sEXPORTED_RUNTIME_METHODS=["HEAPF32"]' --js-library web/odin-library.js --shell-file web/shell.html --preload-file assets
    if ($LASTEXITCODE -ne 0) { throw "Emscripten linking failed." }
    Write-Host "Web build ready in $Output. Serve with: python -m http.server 8000 --directory $Output"
} finally { Pop-Location }
