#!/usr/bin/env bash
set -euo pipefail

# Append account<->proxy binding audit records (JSONL)
# Usage:
#   audit_account_proxy_binding.sh <event> <profileId> [proxy_raw] [proxy_normalized] [ip] [status] [reason]

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
AUDIT_FILE="${OCX_ACCOUNT_PROXY_AUDIT_FILE:-$BASE_DIR/reports/account-proxy-audit.jsonl}"

EVENT="${1:-}"
PROFILE_ID="${2:-}"
PROXY_RAW="${3:-}"
PROXY_NORMALIZED="${4:-}"
IP="${5:-}"
STATUS="${6:-}"
REASON="${7:-}"

if [[ -z "$EVENT" || -z "$PROFILE_ID" ]]; then
  echo "usage: $0 <event> <profileId> [proxy_raw] [proxy_normalized] [ip] [status] [reason]" >&2
  exit 2
fi

mkdir -p "$(dirname "$AUDIT_FILE")"

TS_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HOST="$(hostname 2>/dev/null || echo unknown)"

TS_NOW="$TS_NOW" HOST="$HOST" PROFILE_ID="$PROFILE_ID" EVENT="$EVENT" PROXY_RAW="$PROXY_RAW" PROXY_NORMALIZED="$PROXY_NORMALIZED" IP="$IP" STATUS="$STATUS" REASON="$REASON" AUDIT_FILE="$AUDIT_FILE" node - <<'NODE'
const fs=require('fs');
const rec={
  ts: process.env.TS_NOW,
  host: process.env.HOST,
  profileId: process.env.PROFILE_ID,
  event: process.env.EVENT,
  proxyRaw: process.env.PROXY_RAW || null,
  proxyNormalized: process.env.PROXY_NORMALIZED || null,
  egressIp: process.env.IP || null,
  status: process.env.STATUS || null,
  reason: process.env.REASON || null,
};
fs.appendFileSync(process.env.AUDIT_FILE, JSON.stringify(rec)+'\n');
NODE
