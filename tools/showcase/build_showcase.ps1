param(
    [string]$GodotPath = "godot",
    [string]$PythonPath = "python"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

& $GodotPath `
    --path $projectRoot `
    --audio-driver Dummy `
    --rendering-method gl_compatibility `
    --script "res://tools/showcase/capture_showcase.gd"

& $PythonPath (Join-Path $PSScriptRoot "generate_showcase.py")
