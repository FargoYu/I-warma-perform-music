param(
    [string]$GodotPath = 'D:\Games\Steam\steamapps\common\Godot Engine\godot.exe'
)

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot was not found at $GodotPath. Pass -GodotPath with its actual location."
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$fixturePath = Join-Path $tempRoot ('warma-painter-' + [Guid]::NewGuid().ToString('N'))
$testExitCode = 1
try {
    foreach ($folder in @('', 'addons\block_painter', 'addons\test_driver', 'objects', 'Assets\Sprites', 'fixtures')) {
        New-Item -ItemType Directory -Path (Join-Path $fixturePath $folder) -Force | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'block_painter_fixture\import_project.godot') -Destination (Join-Path $fixturePath 'project.godot')
    Copy-Item -LiteralPath (Join-Path $projectPath 'addons\block_painter\block_painter.gd') -Destination (Join-Path $fixturePath 'addons\block_painter\block_painter.gd')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test_block_painter.gd') -Destination (Join-Path $fixturePath 'addons\test_driver\test_block_painter.gd')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'block_painter_fixture\plugin.cfg') -Destination (Join-Path $fixturePath 'addons\test_driver\plugin.cfg')
    Copy-Item -LiteralPath (Join-Path $projectPath 'objects\block_grid.gd') -Destination (Join-Path $fixturePath 'objects\block_grid.gd')
    Copy-Item -LiteralPath (Join-Path $projectPath 'Assets\Sprites\block.png') -Destination (Join-Path $fixturePath 'Assets\Sprites\block.png')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'block_painter_fixture\grid_base.tscn'), (Join-Path $PSScriptRoot 'block_painter_fixture\level.tscn') -Destination (Join-Path $fixturePath 'fixtures')

    foreach ($phase in @('import', 'test')) {
        if ($phase -eq 'test') {
            # The test phase enables the test driver and needs the full fixture project file.
            # It must not be pre-copied above: the import phase only registers assets.
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'block_painter_fixture\test_project.godot') -Destination (Join-Path $fixturePath 'project.godot')
        }
        $stdoutPath = Join-Path $fixturePath ($phase + '.stdout.log')
        $stderrPath = Join-Path $fixturePath ($phase + '.stderr.log')
        $arguments = @('--headless', '--editor', '--path', ('"' + $fixturePath + '"'))
        if ($phase -eq 'import') { $arguments += @('--import', '--recovery-mode', '--', '--block-painter-import') }
        $process = Start-Process -FilePath $GodotPath -WindowStyle Hidden -PassThru `
            -ArgumentList $arguments -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $null = $process.Handle
        if (-not $process.WaitForExit(60000)) {
            Stop-Process -Id $process.Id -Force
            throw "Block painter $phase exceeded its 60 second timeout."
        }
        $process.WaitForExit()
        $output = Get-Content -LiteralPath $stdoutPath -Raw
        $errors = Get-Content -LiteralPath $stderrPath -Raw
        Write-Output $output
        if ($errors) { Write-Output $errors }
        if ($process.ExitCode -ne 0 -or $errors -match 'SCRIPT ERROR|Parse Error|ERROR:') {
            throw "Block painter $phase failed with exit code $($process.ExitCode)."
        }
        if ($phase -eq 'test') {
            $testExitCode = if ($output -match 'BLOCK_PAINTER: \d+ cases, \d+ checks, 0 failures') { 0 } else { 1 }
        }
    }
} finally {
    # Only remove this runner's unique, resolved directory below the system Temp.
    if (Test-Path -LiteralPath $fixturePath -PathType Container) {
        $resolved = (Resolve-Path -LiteralPath $fixturePath).ProviderPath
        $parent = [System.IO.Path]::GetFullPath((Split-Path -Parent $resolved)) + [System.IO.Path]::DirectorySeparatorChar
        $expectedParent = $tempRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if ($parent -ne $expectedParent -or (Split-Path -Leaf $resolved) -notmatch '^warma-painter-[0-9a-f]{32}$') {
            throw "Refusing to remove unexpected fixture directory: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
exit $testExitCode
