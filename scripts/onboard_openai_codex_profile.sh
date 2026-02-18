#!/usr/bin/env bash
set -euo pipefail

# Add/replace a profile after decommission.
# Usage:
#   onboard_openai_codex_profile.sh openai-codex:acc03 [/path/to/auth.json]

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
PROVIDER="${OCX_PROVIDER:-openai-codex}"
PROFILE_ID="${1:-}"
DEFAULT_AUTH_JSON_PATH="${OCX_CODEX_AUTH_PATH:-/root/.codex/auth.json}"
AUTH_JSON_PATH="${2:-$DEFAULT_AUTH_JSON_PATH}"
AUTH_MAP_FILE="${OCX_AUTH_MAP_FILE:-$BASE_DIR/config/openai-codex-auth-map.env}"

if [[ -z "$PROFILE_ID" ]]; then
  echo "usage: $0 <profileId> [auth.json path]" >&2
  exit 2
fi
if [[ "$PROFILE_ID" != ${PROVIDER}:* ]]; then
  echo "profileId must start with ${PROVIDER}:" >&2
  exit 2
fi

if [[ ! -x "$BASE_DIR/scripts/import_codex_auth_to_openclaw.sh" ]]; then
  echo "missing: $BASE_DIR/scripts/import_codex_auth_to_openclaw.sh" >&2
  exit 2
fi

if [[ ! -f "$AUTH_JSON_PATH" ]]; then
  echo "auth file not found: $AUTH_JSON_PATH" >&2
  echo "run this first, then rerun onboard:"
  echo "  codex logout && codex -c cli_auth_credentials_store='file' login --device-auth"
  exit 1
fi

"$BASE_DIR/scripts/import_codex_auth_to_openclaw.sh" "$PROFILE_ID" main "$AUTH_JSON_PATH"

# update map file for future auto-repair
mkdir -p "$(dirname "$AUTH_MAP_FILE")"
touch "$AUTH_MAP_FILE"
awk -F= -v k="$PROFILE_ID" '$1!=k' "$AUTH_MAP_FILE" > "$AUTH_MAP_FILE.tmp" || true
echo "$PROFILE_ID=$AUTH_JSON_PATH" >> "$AUTH_MAP_FILE.tmp"
mv "$AUTH_MAP_FILE.tmp" "$AUTH_MAP_FILE"

# sync order
if [[ -x "$BASE_DIR/scripts/sync_openclaw_auth_order.sh" ]]; then
  "$BASE_DIR/scripts/sync_openclaw_auth_order.sh" "$PROVIDER" main >/dev/null 2>&1 || true
fi

# quick verify
openclaw models status --json | node -e "const fs=require('fs');const d=JSON.parse(fs.readFileSync(0,'utf8'));const p='${PROFILE_ID}';const ok=((d.auth?.oauth?.profiles||[]).some(x=>x.profileId===p));console.log(ok?'onboard ok: '+p:'onboard maybe failed: '+p);process.exit(ok?0:1)"

# optional post-onboard health verify (no notify)
if [[ -x "$BASE_DIR/scripts/healthcheck_openai_codex_pool.sh" ]]; then
  OCX_DRY_RUN=1 "$BASE_DIR/scripts/healthcheck_openai_codex_pool.sh" >/dev/null 2>&1 || true
fi

echo "post-onboard verify done"
