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
    foreach ($existing in Get-ChildItem -LiteralPath $Output -Force) {
        if ($existing.PSIsContainer -or $existing.Name -notin $allowed) {
            throw "Unexpected file in site output: $($existing.Name). Choose a fresh -Output folder."
        }
    }
    foreach ($entry in $sources.GetEnumerator()) {
        Copy-Item -LiteralPath $entry.Value -Destination (Join-Path $Output $entry.Key) -Force
    }
    Set-Content -LiteralPath (Join-Path $Output '.nojekyll') -Value '' -NoNewline
    Write-Host "Public site prepared in $Output ($($allowed.Count) files)."
} finally { Pop-Location }
