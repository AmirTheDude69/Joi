# Joi — a Codex pet

Joi is a soft 3D chibi Codex v2 pet: natural copper-ginger double buns, round glasses, a bright smile, a black buttoned vest, loose white trousers, and tiny white shoes.

![Joi animation contact sheet](preview.png)

## Install on macOS or Linux

1. On this repository page, choose **Code → Download ZIP** and extract the ZIP.
2. Open Terminal in the extracted folder.
3. Run:

   ```bash
   chmod +x install.sh
   ./install.sh
   ```

4. Completely quit and reopen Codex.
5. Open the pet selector in Codex and choose **Joi**.

If `CODEX_HOME` is set, the installer uses it. Otherwise Joi is installed to `~/.codex/pets/joi`.

## Install on Windows

1. Choose **Code → Download ZIP** and extract the ZIP.
2. Right-click the extracted folder and choose **Open in Terminal**.
3. Run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```

4. Completely quit and reopen Codex.
5. Open the pet selector in Codex and choose **Joi**.

The default destination is `%USERPROFILE%\.codex\pets\joi`, or `%CODEX_HOME%\pets\joi` when `CODEX_HOME` is set.

## Manual installation

Copy `pet.json` and `spritesheet.webp` into a folder named `joi` inside your Codex pets directory:

- macOS/Linux: `~/.codex/pets/joi/`
- Windows: `%USERPROFILE%\.codex\pets\joi\`

Then restart Codex and select Joi.

## Animation states

Codex drives pet animations from its own task state; the manifest does not expose a public command that forces a specific animation. Joi responds automatically while Codex is idle, waiting, working, reviewing, succeeding, or failing. Her special gestures are distributed across those states, including a wink, double wave, heart hands, a joyful hop, and a blown kiss.

## Package contents

- `pet.json` — Codex v2 pet manifest
- `spritesheet.webp` — `1536 × 2288` animated sprite atlas
- `preview.png` — contact-sheet preview
- `install.sh` — macOS/Linux installer
- `install.ps1` — Windows installer

This repository contains the finished pet artwork only. The source photographs used to design it are not included.

