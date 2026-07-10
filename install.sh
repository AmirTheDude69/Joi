#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CODEX_ROOT=${CODEX_HOME:-"$HOME/.codex"}
DESTINATION="$CODEX_ROOT/pets/joi"

if [ ! -f "$SCRIPT_DIR/pet.json" ] || [ ! -f "$SCRIPT_DIR/spritesheet.webp" ]; then
  echo "Joi's package files are missing. Run this installer from the extracted repository folder." >&2
  exit 1
fi

mkdir -p "$DESTINATION"
cp "$SCRIPT_DIR/pet.json" "$DESTINATION/pet.json"
cp "$SCRIPT_DIR/spritesheet.webp" "$DESTINATION/spritesheet.webp"

echo "Joi was installed to $DESTINATION"
echo "Quit and reopen Codex, then choose Joi from the pet selector."

