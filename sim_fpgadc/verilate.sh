#!/usr/bin/env bash
set -euo pipefail
clear

OBJ_DIR=out/obj_dir
MANIFEST="$OBJ_DIR/Vsimtop__verFiles.dat"

mkdir -p "$OBJ_DIR"

verilator --public --compiler msvc --converge-limit 2000 \
  -Wno-UNSIGNED -Wno-PINMISSING -Wno-WIDTH \
  --exe sim_main.cpp \
  -I. -I.. -Ish4 -I../rtl -I../rtl/cpu -I../rtl/fpu -I../rtl/pvr \
  --top-module simtop -Mdir "$OBJ_DIR" --cc simtop.v

# Verilator skips rewriting identical files by default. Keep out/obj_dir intact
# for MSBuild incremental compiles, but remove generated sources/headers that
# are no longer present in the latest Verilator manifest so globs do not pick
# up stale Vsimtop files.
if [[ -f "$MANIFEST" ]]; then
  keep_list=$(mktemp)
  awk -F'"' '/^T / { n = split($2, parts, "/"); base = parts[n]; if (base ~ /^Vsimtop.*\.(cpp|h)$/) print base }' "$MANIFEST" | sort -u > "$keep_list"

  while IFS= read -r -d '' file; do
    base=$(basename "$file")
    if ! grep -Fxq "$base" "$keep_list"; then
      rm -f "$file"
    fi
  done < <(find "$OBJ_DIR" -maxdepth 1 -type f \( -name 'Vsimtop*.cpp' -o -name 'Vsimtop*.h' \) -print0)

  rm -f "$keep_list"
fi
