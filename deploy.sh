#!/usr/bin/env bash
# deploy.sh — sync TownGeneratorOS build to an environment target (UAT or Prod) on my host, thoughtrights.com
#
# Usage:  ./deploy.sh [uat|prod] [--dry-run]
#
#   ./deploy.sh              -> UAT  (default; all new changes go here first)
#   ./deploy.sh prod         -> PRODUCTION (explicit; asks for confirmation)
#   ./deploy.sh [uat|prod] --dry-run
#
# Environments:
#   uat  -> thoughtrights:build/TownGeneratorOS-uat/  -> https://www.dungeoneer.com/city-map-uat/
#   prod -> thoughtrights:build/TownGeneratorOS/      -> https://www.dungeoneer.com/city-map/
#

set -euo pipefail

TARGET="uat"
DRY=""

# Parse args: first non-flag is the target; --dry-run anywhere.
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY="--dry-run" ;;
    uat|prod)  TARGET="$arg" ;;
    *) echo "Unknown arg: $arg (use 'uat', 'prod', or '--dry-run')"; exit 1 ;;
  esac
done

if [[ "$TARGET" == "prod" ]]; then
  REMOTE="thoughtrights:build/TownGeneratorOS/"
  URL="https://www.dungeoneer.com/city-map/"
else
  REMOTE="thoughtrights:build/TownGeneratorOS-uat/"
  URL="https://www.dungeoneer.com/city-map-uat/"
fi

# Production is a deliberate promotion — confirm before touching it.
if [[ "$TARGET" == "prod" && -z "$DRY" ]]; then
  echo "⚠  About to deploy to PRODUCTION ($REMOTE)."
  read -r -p "   Type 'yes' to promote to production: " ans
  [[ "$ans" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

if [[ -n "$DRY" ]]; then
  echo "==> DRY RUN — no files will be transferred"
fi

echo "==> Target: $TARGET"
echo "==> Syncing to $REMOTE"


rsync -avz $DRY \
  --exclude='.git/' \
  --exclude='.claude/' \
  --exclude='references/' \
  --exclude='SKILL.md' \
  --exclude='SKILL-dev.md' \
  --exclude='SKILL-collaboration.md' \
  --exclude='SKILL-discord.md' \
  --exclude='README.md' \
  --exclude='reminders.txt' \
  --exclude='coffer-prototype.html' \
  --exclude='tag-coffers.html' \
  --exclude='tag-server.py' \
  --exclude='deploy.sh' \
  --exclude='api/register_commands.py' \
  --exclude='*.pyc' \
  --exclude='__pycache__/' \
  --exclude='*.xcf' \
  --exclude='_data/' \
  --exclude='*.db' --exclude='*.db-wal' --exclude='*.db-shm' \
  --exclude='tests/' \
  --exclude='pytest.ini' \
  --exclude='requirements-dev.txt' \
  --exclude='run-tests.sh' \
  --exclude='.pytest_cache/' \
  --exclude='.DS_Store' \
  ./Export/html5/bin/ "$REMOTE"

echo ""
echo "==> Done."
if [[ -z "$DRY" ]]; then
  echo "    Live at: $URL"
fi
