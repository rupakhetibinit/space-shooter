param([string]$Output = "build/pages")
$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
try {
    $sources = [ordered]@{
        'index.html' = 'build/web/index.html'
        'index.js' = 'build/web/index.js'
        'index.wasm' = 'build/web/index.wasm'
        'index.data' = 'build/web/index.data'
        'odin.js' = 'build/web/odin.js'
        'editor/index.html' = 'build/web/editor/index.html'
        'editor/index.js' = 'build/web/editor/index.js'
        'editor/index.wasm' = 'build/web/editor/index.wasm'
        'editor/index.data' = 'build/web/editor/index.data'
        'editor/odin.js' = 'build/web/editor/odin.js'
        'campaign.json' = 'assets/campaign.json'
        'starter-campaign.json' = 'examples/starter-campaign.json'
        'LEVELS.md' = 'LEVELS.md'
        'BEHAVIOR.md' = 'BEHAVIOR.md'
    }
    foreach ($source in $sources.Values) {
        if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing site input: $source. Build the web game first." }
    }
    New-Item -ItemType Directory -Force $Output | Out-Null
    $allowed = @($sources.Keys) + '.nojekyll'
    foreach ($existing in Get-ChildItem -LiteralPath $Output -Recurse -Force) {
        $relative = [IO.Path]::GetRelativePath((Resolve-Path $Output), $existing.FullName).Replace('\','/')
        if ($existing.PSIsContainer) {
            if ($relative -ne 'editor') { throw "Unexpected directory in site output: $relative. Choose a fresh -Output folder." }
        } elseif ($relative -notin $allowed) { throw "Unexpected file in site output: $relative. Choose a fresh -Output folder." }
    }
    foreach ($entry in $sources.GetEnumerator()) {
        $destination = Join-Path $Output $entry.Key
        New-Item -ItemType Directory -Force (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $entry.Value -Destination $destination -Force
    }
    Set-Content -LiteralPath (Join-Path $Output '.nojekyll') -Value '' -NoNewline
    Write-Host "Public site prepared in $Output ($($allowed.Count) files; player and creator routes)."
} finally { Pop-Location }
