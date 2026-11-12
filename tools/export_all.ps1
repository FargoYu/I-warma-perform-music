param(
    [string]$Godot = "",
    [ValidateSet("all", "windows", "android", "web")][string]$Platform = "all"
)
$ErrorActionPreference = "Stop"
$exportArgs = @("$PSScriptRoot/export_all.py", "--platform", $Platform)
if ($Godot) { $exportArgs += @("--godot", $Godot) }
python @exportArgs
if ($LASTEXITCODE -ne 0) { throw "Export failed; inspect build logs." }
