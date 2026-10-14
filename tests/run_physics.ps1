param(
    [string]$GodotPath = 'D:\Games\Steam\steamapps\common\Godot Engine\godot.exe'
)

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot was not found at $GodotPath. Pass -GodotPath with its actual location."
}

# The Windows GUI executable detaches when invoked directly with &, so wait for
# the real process and preserve its exit code for automated verification.
$stdoutPath = [System.IO.Path]::GetTempFileName()
$stderrPath = [System.IO.Path]::GetTempFileName()
$testExitCode = 1
try {
    $testProcess = Start-Process -FilePath $GodotPath -WindowStyle Hidden -Wait -PassThru `
        -ArgumentList @('--headless', '--path', ('"' + $projectPath + '"'), '--script', 'res://tests/test_physics.gd') `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $testOutput = Get-Content -LiteralPath $stdoutPath -Raw
    $testErrors = Get-Content -LiteralPath $stderrPath -Raw
    Write-Output $testOutput
    if ($testErrors) { Write-Output $testErrors }
    $testExitCode = $testProcess.ExitCode
    if ($testOutput -notmatch 'PHYSICS: \d+ cases, \d+ checks, 0 failures' -or $testErrors -match 'SCRIPT ERROR|Parse Error') {
        $testExitCode = 1
    }
} finally {
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
}
exit $testExitCode
