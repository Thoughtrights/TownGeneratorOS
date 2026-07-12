#!/usr/bin/env bash
# start-dev.sh — serve the html5 build locally for development.
#
# Usage:  ./start-dev.sh [port]     (default port: 8123)
#
# Serves Export/html5/bin at http://localhost:<port>/
# Rebuild the app with:  haxelib run lime build html5

set -euo pipefail

PORT="${1:-8123}"
DIR="$(cd "$(dirname "$0")" && pwd)/Export/html5/bin"

if [[ ! -f "$DIR/index.html" ]]; then
  echo "No build found at $DIR"
  echo "Run 'haxelib run lime build html5' first."
  exit 1
fi

echo "Serving $DIR"
echo "  -> http://localhost:$PORT/"
exec python3 -m http.server "$PORT" --directory "$DIR"
