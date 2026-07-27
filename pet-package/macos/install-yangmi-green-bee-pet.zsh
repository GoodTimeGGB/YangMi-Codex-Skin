#!/usr/bin/env zsh
set -euo pipefail

root="${0:A:h:h}"
source="$root/yangmi-green-bee"
destination="$HOME/.codex/pets/yangmi-green-bee"

[[ -f "$source/pet.json" && -f "$source/spritesheet.webp" ]] || { print -u2 "Pet package is incomplete: $source"; exit 1; }
mkdir -p "$destination"
cp "$source/pet.json" "$destination/pet.json"
cp "$source/spritesheet.webp" "$destination/spritesheet.webp"
print 'Yang Mi Green Bee has been installed. Restart Codex, then select the pet in Codex settings.'
