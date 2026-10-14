param(
    [string]$GodotPath = '',
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) {
    foreach ($name in @('godot.windows.opt.tools.64.exe', 'godot.exe')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { $GodotPath = $command.Source; break }
    }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Pass -GodotPath with the path to Godot 4.7.2 and install its matching Windows export templates.'
}
$logPath = Join-Path $projectPath 'artifacts\release'
$distPath = Join-Path $projectPath 'dist'
$packageName = 'Warma-Demo-v0.2-Windows-x86_64'
$packagePath = Join-Path $distPath $packageName
$exePath = Join-Path $packagePath 'Warma-Demo-v0.2.exe'
New-Item -ItemType Directory -Force -Path $logPath, $packagePath | Out-Null
foreach ($directory in @((Split-Path -Parent $logPath), $distPath)) {
    Set-Content -LiteralPath (Join-Path $directory '.gdignore') -Value ''
}

function Invoke-GodotChecked([string]$Name, [string[]]$Arguments, [int]$TimeoutSeconds = 60) {
    $stdout = Join-Path $logPath ($Name + '.log')
    $stderr = Join-Path $logPath ($Name + '.errors.log')
    $process = Start-Process -FilePath $GodotPath -WindowStyle Hidden -PassThru `
        -ArgumentList $Arguments -WorkingDirectory $projectPath `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $null = $process.Handle
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $process.Id -Force
        throw "$Name exceeded its timeout. See $logPath"
    }
    $process.WaitForExit()
    $errors = Get-Content -LiteralPath $stderr -Raw
    if ($process.ExitCode -ne 0 -or $errors -match 'SCRIPT ERROR|Parse Error|ERROR:.*export') {
        throw "$Name failed. See $stdout and $stderr"
    }
    Write-Output "$Name passed"
}

$quotedProject = '"' + $projectPath + '"'
Invoke-GodotChecked 'import' @('--headless', '--path', $quotedProject, '--editor', '--import')
if (-not $SkipTests) {
    foreach ($suite in @('physics', 'level_loading', 'gameplay', 'real_input', 'display', 'block_painter')) {
        $runner = Join-Path $projectPath ('tests\run_' + $suite + '.ps1')
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -GodotPath $GodotPath 2>&1
        $output | Set-Content -LiteralPath (Join-Path $logPath ($suite + '.log'))
        if ($LASTEXITCODE -ne 0) { throw "$suite failed. See $logPath" }
        Write-Output "$suite passed"
    }
    Invoke-GodotChecked 'audio' @('--headless', '--path', $quotedProject, '--script', 'res://tests/test_audio.gd')
    if ((Get-Content -LiteralPath (Join-Path $logPath 'audio.log') -Raw) -notmatch 'AUDIO: \d+ checks, 0 failures') {
        throw 'Audio suite did not report success.'
    }
    Invoke-GodotChecked 'end_screen' @('--headless', '--path', $quotedProject, '--script', 'res://tests/test_end_screen.gd')
    if ((Get-Content -LiteralPath (Join-Path $logPath 'end_screen.log') -Raw) -notmatch 'END SCREEN: .*0 failures') {
        throw 'Ending screen suite did not report success.'
    }
}
Invoke-GodotChecked 'export' @('--headless', '--path', $quotedProject, '--export-release', '"Windows Desktop"', ('"' + $exePath + '"'))
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw 'Export did not produce an executable.' }

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'release_readme.txt') -Destination (Join-Path $packagePath 'README.txt')
Copy-Item -LiteralPath (Join-Path $projectPath 'RELEASE_NOTES.md') -Destination (Join-Path $packagePath 'RELEASE_NOTES.md')

# Run the embedded PCK from the package directory, away from project.godot.
$smokeOut = Join-Path $logPath 'release_smoke.log'
$smokeErr = Join-Path $logPath 'release_smoke.errors.log'
$smoke = Start-Process -FilePath $exePath -WindowStyle Hidden -PassThru -WorkingDirectory $packagePath `
    -ArgumentList @('--headless', '--quit-after', '20') -RedirectStandardOutput $smokeOut -RedirectStandardError $smokeErr
$null = $smoke.Handle
if (-not $smoke.WaitForExit(15000)) { Stop-Process -Id $smoke.Id -Force; throw 'Exported game startup timed out.' }
$smoke.WaitForExit()
if ($smoke.ExitCode -ne 0 -or (Get-Content -LiteralPath $smokeErr -Raw) -match 'ERROR:') {
    throw 'Exported game failed its standalone startup check.'
}
Write-Output 'Standalone release startup passed'

$auditOut = Join-Path $logPath 'release_audit.log'
$auditErr = Join-Path $logPath 'release_audit.errors.log'
$auditScript = Join-Path $projectPath 'tests\test_release.gd'
# Release templates ignore editor-only --script. Use the matching tools binary
# to inspect the exported pack, after checking the actual EXE independently.
$audit = Start-Process -FilePath $GodotPath -WindowStyle Hidden -PassThru -WorkingDirectory $packagePath `
    -ArgumentList @('--headless', '--main-pack', ('"' + $exePath + '"'), '--script', ('"' + $auditScript + '"')) -RedirectStandardOutput $auditOut -RedirectStandardError $auditErr
$null = $audit.Handle
if (-not $audit.WaitForExit(15000)) { Stop-Process -Id $audit.Id -Force; throw 'Exported game route check timed out.' }
$audit.WaitForExit()
if ($audit.ExitCode -ne 0 -or (Get-Content -LiteralPath $auditErr -Raw) -match 'SCRIPT ERROR|Parse Error' -or
    (Get-Content -LiteralPath $auditOut -Raw) -notmatch 'RELEASE SMOKE: \d+ checks, 0 failures') {
    throw 'Exported game failed its embedded resource and room route checks.'
}
Write-Output 'Exported resource and room route checks passed'

$zipPath = Join-Path $distPath ($packageName + '.zip')
Compress-Archive -LiteralPath $packagePath -DestinationPath $zipPath -Force
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($zipPath + '.sha256') -Value ($hash + '  ' + (Split-Path -Leaf $zipPath)) -Encoding ASCII
Write-Output "Release package: $zipPath"
