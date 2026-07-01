#!/usr/bin/env bash
set -euo pipefail
clear

OBJ_DIR=out/obj_dir
MANIFEST="$OBJ_DIR/Vsimtop__verFiles.dat"
VCXPROJ="ConsoleApplication1/ConsoleApplication1.vcxproj"
FILTERS="ConsoleApplication1/ConsoleApplication1.vcxproj.filters"
SCRIPT="$(dirname "$0")/update_vcxproj.py"

mkdir -p "$OBJ_DIR"

verilator --public --compiler msvc --converge-limit 2000 \
  -Wno-UNSIGNED -Wno-PINMISSING -Wno-WIDTH \
  --exe sim_main.cpp \
  -I. -I.. -Ish4 -I../rtl -I../rtl/cpu -I../rtl/fpu -I../rtl/pvr \
  --top-module simtop -Mdir "$OBJ_DIR" --cc simtop.v

# Remove stale Vsimtop files that Verilator no longer generates.
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

# Rewrite MSVC project files from the manifest — no manual editing needed.
# Prefer a real installation over the Windows Store stub (which exits 49).
PYTHON=$(ls /c/Users/*/AppData/Local/Programs/Python/Python3*/python.exe 2>/dev/null | sort -rV | head -1 || true)
if [[ -z "$PYTHON" ]]; then
  PYTHON=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)
fi

if [[ -n "$PYTHON" && -f "$SCRIPT" ]]; then
  "$PYTHON" "$SCRIPT" "$MANIFEST" "$VCXPROJ" "$FILTERS"
else
  echo "WARNING: Python not found or update_vcxproj.py missing — skipping MSVC project update." >&2
fi
