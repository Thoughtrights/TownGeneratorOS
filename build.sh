#!/usr/bin/env bash
# build.sh — build the html5 target with the pinned toolchain in ~/.towngen.
# Run ./setup-toolchain.sh once first (or whenever the toolchain breaks).

set -euo pipefail

TOOL=~/.towngen
if [[ ! -x "$TOOL/haxe415/haxe" ]]; then
  echo "Toolchain missing — run ./setup-toolchain.sh first."
  exit 1
fi

export PATH="$TOOL/haxe415:$PATH"
export HAXE_STD_PATH="$TOOL/haxe415/std"
export HAXELIB_PATH="$TOOL/haxelib_repo"

cd "$(dirname "$0")"
exec haxelib run lime build html5 "$@"
