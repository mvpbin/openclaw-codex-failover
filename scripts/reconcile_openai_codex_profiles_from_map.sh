#!/usr/bin/env bash
set -euo pipefail

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
PROVIDER="${OCX_PROVIDER:-openai-codex}"
AGENT="${OCX_AGENT:-main}"
AUTH_MAP_FILE="${OCX_AUTH_MAP_FILE:-$BASE_DIR/config/openai-codex-auth-map.env}"
AUTH_PROFILES_PATH="${OCX_AUTH_PROFILES_PATH:-/root/.openclaw/agents/${AGENT}/agent/auth-profiles.json}"
LOCK_FILE="${OCX_RECONCILE_LOCK_FILE:-$BASE_DIR/run/openai_codex_reconcile.lock}"
RECONCILE_MODE="${OCX_RECONCILE_MODE:-missing-only}" # missing-only | ensure-all

mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "reconcile skipped: lock held ($LOCK_FILE)" >&2
  exit 0
fi

if [[ ! -f "$AUTH_MAP_FILE" ]]; then
  echo "auth map not found: $AUTH_MAP_FILE" >&2
  exit 1
fi

mapfile -t pairs < <(awk -F= -v pfx="${PROVIDER}:" 'index($1,pfx)==1 && NF>=2 {print $1"\t"substr($0,index($0,$2))}' "$AUTH_MAP_FILE")
if (( ${#pairs[@]} == 0 )); then
  echo "no mapped profiles for $PROVIDER in $AUTH_MAP_FILE"
  exit 0
fi

declare -A current_profiles
if [[ -f "$AUTH_PROFILES_PATH" ]]; then
  while IFS= read -r id; do
    [[ -n "$id" ]] && current_profiles["$id"]=1
  done < <(AUTH_PROFILES_PATH="$AUTH_PROFILES_PATH" PREFIX="${PROVIDER}:" node - <<'NODE'
const fs=require('fs');
const p=process.env.AUTH_PROFILES_PATH;
const prefix=String(process.env.PREFIX||'openai-codex:');
let j={};
try{j=JSON.parse(fs.readFileSync(p,'utf8'));}catch{}
for(const id of Object.keys(j.profiles||{})) if(String(id).startsWith(prefix)) console.log(id);
NODE
)
fi

imported=0
skipped=0
failed=0

for row in "${pairs[@]}"; do
  IFS=$'\t' read -r profile auth_path <<< "$row"
  [[ -n "$profile" && -n "$auth_path" ]] || continue

  if [[ "$RECONCILE_MODE" == "missing-only" && -n "${current_profiles[$profile]:-}" ]]; then
    skipped=$((skipped+1))
    continue
  fi

  if [[ ! -f "$auth_path" ]]; then
    echo "missing auth file for $profile: $auth_path" >&2
    failed=$((failed+1))
    continue
  fi

  if OCX_IMPORT_SKIP_MODELS_STATUS=1 "$BASE_DIR/scripts/import_codex_auth_to_openclaw.sh" "$profile" "$AGENT" "$auth_path" >/dev/null 2>&1; then
    imported=$((imported+1))
  else
    echo "import failed for $profile from $auth_path" >&2
    failed=$((failed+1))
  fi
done

if [[ -x "$BASE_DIR/scripts/sync_openclaw_auth_order.sh" ]]; then
  "$BASE_DIR/scripts/sync_openclaw_auth_order.sh" "$PROVIDER" "$AGENT" >/dev/null 2>&1 || true
fi

echo "reconcile done: imported=$imported skipped=$skipped failed=$failed mode=$RECONCILE_MODE"
if (( failed > 0 )); then
  exit 1
fi
