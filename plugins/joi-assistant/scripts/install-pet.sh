#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PLUGIN_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SOURCE="$PLUGIN_ROOT/assets/pet"
CODEX_ROOT=${CODEX_HOME:-"$HOME/.codex"}
DESTINATION="$CODEX_ROOT/pets/joi"

if [ ! -f "$SOURCE/pet.json" ] || [ ! -f "$SOURCE/spritesheet.webp" ]; then
  echo "Joi's bundled pet assets are missing." >&2
  exit 1
fi

mkdir -p "$DESTINATION"
cp "$SOURCE/pet.json" "$DESTINATION/pet.json"
cp "$SOURCE/spritesheet.webp" "$DESTINATION/spritesheet.webp"

echo "Joi was installed to $DESTINATION"
echo "Quit and reopen Codex, then choose Joi from the pet selector."
