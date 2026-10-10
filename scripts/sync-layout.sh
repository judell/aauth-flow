#!/bin/bash
# Move the newest browser download of layout.json into this repo.
set -euo pipefail
dl="$HOME/Downloads"
repo="$(cd "$(dirname "$0")/.." && pwd)"
shopt -s nullglob
files=("$dl/layout.json" "$dl"/layout\ \(*\).json)
existing=(); for f in "${files[@]}"; do [ -e "$f" ] && existing+=("$f"); done
[ ${#existing[@]} -gt 0 ] || { echo "No layout download in $dl"; exit 1; }
newest=$(ls -t "${existing[@]}" | head -1)
for f in "${existing[@]}"; do [ "$f" = "$newest" ] || rm -- "$f"; done
[ "$newest" = "$dl/layout.json" ] || mv -- "$newest" "$dl/layout.json"
cp "$dl/layout.json" "$repo/layout.json"
echo "Used $(basename "$newest") -> layout.json"
