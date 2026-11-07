param([switch]$Check, [string]$Formatter = $env:ODINFMT)
$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
try {
    if (!$Formatter) {
        $command = Get-Command odinfmt -ErrorAction SilentlyContinue
        if ($command) { $Formatter = $command.Source }
    }
    if (!$Formatter) {
        # OLS commonly lives beside Odin and includes the formatter binary.
        $odinRoot = (& odin root).Trim()
        $candidate = Join-Path (Split-Path -Parent $odinRoot) 'ols/odinfmt.exe'
        if (Test-Path -LiteralPath $candidate) { $Formatter = $candidate }
    }
    if (!$Formatter) { throw 'odinfmt not found. Add it to PATH, set ODINFMT, or pass -Formatter <executable>.' }
    $files = @(& git ls-files --cached --others --exclude-standard -- '*.odin') | Sort-Object -Unique
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate Odin files.' }
    $unformatted = @()
    foreach ($file in $files) {
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = $Formatter
        $info.WorkingDirectory = $PSScriptRoot
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        if (!$Check) { $info.ArgumentList.Add('-w') }
        $info.ArgumentList.Add($file)
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $info
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $formatted = $stdout.GetAwaiter().GetResult()
        $errors = $stderr.GetAwaiter().GetResult()
        $code = $process.ExitCode
        $process.Dispose()
        if ($code -ne 0) { throw "odinfmt failed on ${file}: $errors" }
        if ($Check) {
            $original = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $file))
            if ($original.Replace("`r`n", "`n").TrimEnd("`n") -cne $formatted.Replace("`r`n", "`n").TrimEnd("`n")) { $unformatted += $file }
        } else { Write-Host "Formatted $file" }
    }
    if ($unformatted.Count) { throw "Run ./format-odin.ps1 before pushing: $($unformatted -join ', ')" }
    if ($Check) { Write-Host "All $($files.Count) Odin files are formatted." }
} finally { Pop-Location }

