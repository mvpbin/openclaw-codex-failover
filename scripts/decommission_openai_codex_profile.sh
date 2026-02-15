#!/usr/bin/env bash
set -euo pipefail

# Decommission a bad/banned profile from OpenClaw auth store safely.
# Usage:
#   decommission_openai_codex_profile.sh openai-codex:acc03 [reason]

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

PROFILE_ID="${1:-}"
REASON="${2:-banned_or_invalid}"
if [[ -z "$PROFILE_ID" ]]; then
  echo "usage: $0 <profileId> [reason]" >&2
  exit 2
fi
if [[ "$PROFILE_ID" != openai-codex:* ]]; then
  echo "only openai-codex:* is supported now" >&2
  exit 2
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
BACKUP_DIR="$BASE_DIR/backups"
mkdir -p "$BACKUP_DIR" "$BASE_DIR/reports"

STORE_PATH="$(openclaw models status --json | node -e "const fs=require('fs');const d=JSON.parse(fs.readFileSync(0,'utf8'));process.stdout.write(String(d.auth?.storePath||''));")"
if [[ -z "$STORE_PATH" || ! -f "$STORE_PATH" ]]; then
  echo "auth store not found: $STORE_PATH" >&2
  exit 2
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_FILE="$BACKUP_DIR/auth-profiles.$TS.json"
cp "$STORE_PATH" "$BACKUP_FILE"

STORE_PATH="$STORE_PATH" PROFILE_ID="$PROFILE_ID" node - <<'NODE'
const fs=require('fs');
const p=process.env.STORE_PATH;
const id=process.env.PROFILE_ID;
const j=JSON.parse(fs.readFileSync(p,'utf8'));
if (j.profiles) delete j.profiles[id];
if (j.order && j.order['openai-codex']) j.order['openai-codex']=j.order['openai-codex'].filter(x=>x!==id);
if (j.lastGood && j.lastGood['openai-codex']===id) delete j.lastGood['openai-codex'];
if (j.usageStats) delete j.usageStats[id];
fs.writeFileSync(p, JSON.stringify(j,null,2));
NODE

# best-effort sync
if [[ -x "$BASE_DIR/scripts/sync_openclaw_auth_order.sh" ]]; then
  "$BASE_DIR/scripts/sync_openclaw_auth_order.sh" openai-codex main >/dev/null 2>&1 || true
fi

OUT="$BASE_DIR/reports/openai_codex_decommission_latest.json"
OUT="$OUT" PROFILE_ID="$PROFILE_ID" REASON="$REASON" BACKUP_FILE="$BACKUP_FILE" node - <<'NODE'
const fs=require('fs');
const out={
  ts:new Date().toISOString(),
  action:'decommission',
  profileId:process.env.PROFILE_ID,
  reason:process.env.REASON,
  backup:process.env.BACKUP_FILE
};
fs.writeFileSync(process.env.OUT, JSON.stringify(out,null,2));
NODE

echo "decommissioned: $PROFILE_ID"
echo "backup: $BACKUP_FILE"
echo "report: $OUT"
