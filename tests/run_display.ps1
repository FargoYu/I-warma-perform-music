param(
    [string]$GodotPath = 'D:\Games\Steam\steamapps\common\Godot Engine\godot.exe'
)

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot was not found at $GodotPath. Pass -GodotPath with its actual location."
}

$stdoutPath = [System.IO.Path]::GetTempFileName()
$stderrPath = [System.IO.Path]::GetTempFileName()
$testExitCode = 1
try {
    # A graphics context is required; --headless cannot read actual rendered pixels.
    $testProcess = Start-Process -FilePath $GodotPath -WindowStyle Hidden -PassThru `
        -ArgumentList @('--path', ('"' + $projectPath + '"'), '--script', 'res://tests/test_display.gd') `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    if (-not $testProcess.WaitForExit(60000)) {
        Stop-Process -Id $testProcess.Id -Force
        throw 'Display verification exceeded its 60 second timeout.'
    }
    $testOutput = Get-Content -LiteralPath $stdoutPath -Raw
    $testErrors = Get-Content -LiteralPath $stderrPath -Raw
    Write-Output $testOutput
    if ($testErrors) { Write-Output $testErrors }
    $testExitCode = $testProcess.ExitCode
    if ($testOutput -notmatch 'DISPLAY: \d+ cases, \d+ checks, 0 failures' -or $testErrors -match 'SCRIPT ERROR|Parse Error') {
        $testExitCode = 1
    }
} finally {
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
}
exit $testExitCode
