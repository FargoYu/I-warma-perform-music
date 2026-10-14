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
    $testProcess = Start-Process -FilePath $GodotPath -WindowStyle Hidden -PassThru `
        -ArgumentList @('--headless', '--path', ('"' + $projectPath + '"'), '--script', 'res://tests/test_game.gd') `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    if (-not $testProcess.WaitForExit(60000)) {
        Stop-Process -Id $testProcess.Id -Force
        throw 'Gameplay verification exceeded its 60 second timeout.'
    }
    $testOutput = Get-Content -LiteralPath $stdoutPath -Raw
    $testErrors = Get-Content -LiteralPath $stderrPath -Raw
    Write-Output $testOutput
    if ($testErrors) { Write-Output $testErrors }
    $testExitCode = $testProcess.ExitCode
    if ($testOutput -notmatch 'GAMEPLAY: \d+ cases, \d+ checks, 0 failures' -or $testErrors -match 'SCRIPT ERROR|Parse Error') {
        $testExitCode = 1
    }
} finally {
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
}
exit $testExitCode
