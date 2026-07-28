$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$pluginRoot = Split-Path -Parent $scriptDirectory
$source = Join-Path (Join-Path $pluginRoot "assets") "pet"
$codexRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$destination = Join-Path (Join-Path $codexRoot "pets") "joi"
$manifest = Join-Path $source "pet.json"
$spritesheet = Join-Path $source "spritesheet.webp"

if (-not (Test-Path $manifest) -or -not (Test-Path $spritesheet)) {
    throw "Joi's bundled pet assets are missing."
}

New-Item -ItemType Directory -Force -Path $destination | Out-Null
Copy-Item -Force $manifest (Join-Path $destination "pet.json")
Copy-Item -Force $spritesheet (Join-Path $destination "spritesheet.webp")

Write-Host "Joi was installed to $destination"
Write-Host "Quit and reopen Codex, then choose Joi from the pet selector."
