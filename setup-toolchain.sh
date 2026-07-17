#!/usr/bin/env bash
# setup-toolchain.sh — install the pinned Haxe toolchain for this project
# into ~/.towngen (Haxe 4.1.5 + lime 7.8.0 + openfl 9.0.2 + msignal 1.2.5).
#
# Newer Haxe versions break lime 7.8.0 / openfl 9.0.2, so the toolchain is
# pinned and kept in ~/.towngen (NOT /tmp, which scavenges files).
#
# Usage:  ./setup-toolchain.sh      (idempotent; safe to re-run)
# Then:   ./build.sh                to build html5

set -euo pipefail

TOOL=~/.towngen
HAXE_URL="https://github.com/HaxeFoundation/haxe/releases/download/4.1.5/haxe-4.1.5-osx.tar.gz"

mkdir -p "$TOOL"
cd "$TOOL"

if [[ ! -x "$TOOL/haxe415/haxe" ]]; then
  echo "==> Downloading Haxe 4.1.5"
  curl -sL -o haxe.tar.gz "$HAXE_URL"
  tar -xzf haxe.tar.gz && rm haxe.tar.gz
  mv haxe_* haxe415
fi

export PATH="$TOOL/haxe415:$PATH"
export HAXE_STD_PATH="$TOOL/haxe415/std"
export HAXELIB_PATH="$TOOL/haxelib_repo"

mkdir -p "$TOOL/haxelib_repo"
haxelib --always setup "$TOOL/haxelib_repo" >/dev/null

echo "==> Installing libraries (skips any already present)"
haxelib install lime 7.8.0 --always >/dev/null
haxelib install openfl 9.0.2 --always >/dev/null
haxelib install msignal 1.2.5 --always >/dev/null

echo "==> Toolchain ready:"
haxe -version
haxelib list
