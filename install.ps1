$ErrorActionPreference = "Stop"

$sourceDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$codexRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$destination = Join-Path (Join-Path $codexRoot "pets") "joi"
$manifest = Join-Path $sourceDirectory "pet.json"
$spritesheet = Join-Path $sourceDirectory "spritesheet.webp"

if (-not (Test-Path $manifest) -or -not (Test-Path $spritesheet)) {
    throw "Joi's package files are missing. Run this installer from the extracted repository folder."
}

New-Item -ItemType Directory -Force -Path $destination | Out-Null
Copy-Item -Force $manifest (Join-Path $destination "pet.json")
Copy-Item -Force $spritesheet (Join-Path $destination "spritesheet.webp")

Write-Host "Joi was installed to $destination"
Write-Host "Quit and reopen Codex, then choose Joi from the pet selector."
