#!/usr/bin/env bash
set -euo pipefail

# Repair script for failed openai-codex profiles (non-destructive)
# - Reads failed profiles from latest health report
# - Tries non-interactive import from mapped auth files
# - Outputs manual re-login commands for unresolved accounts

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
REPORT_PATH="${1:-$BASE_DIR/reports/openai_codex_health_latest.json}"
CODEX_AUTH_PATH="${OCX_CODEX_AUTH_PATH:-/root/.codex/auth.json}"
PROVIDER="${OCX_PROVIDER:-openai-codex}"
AUTH_MAP_FILE="${OCX_AUTH_MAP_FILE:-$BASE_DIR/config/openai-codex-auth-map.env}"
TELEGRAM_CHANNEL="${OCX_NOTIFY_CHANNEL:-telegram}"
TELEGRAM_TARGET="${OCX_NOTIFY_TARGET:-182211955}"
DO_NOTIFY="${OCX_REPAIR_NOTIFY:-1}"
DO_RESTART_GATEWAY="${OCX_REPAIR_RESTART_GATEWAY:-0}"
SUGGEST_DECOMMISSION="${OCX_SUGGEST_DECOMMISSION:-0}"

if [[ ! -f "$REPORT_PATH" ]]; then
  echo "report not found: $REPORT_PATH" >&2
  exit 2
fi

mapfile -t FAILED < <(REPORT="$REPORT_PATH" node - <<'NODE'
const fs=require('fs');
const p=process.env.REPORT;
const j=JSON.parse(fs.readFileSync(p,'utf8'));
for(const x of (j.failedProfiles||[])) console.log(String(x));
NODE
)

if ((${#FAILED[@]}==0)); then
  echo "no failed profiles in report, nothing to repair"
  exit 0
fi

mkdir -p "$BASE_DIR/config" "$BASE_DIR/reports"
[[ -f "$AUTH_MAP_FILE" ]] || touch "$AUTH_MAP_FILE"

lookup_auth_path(){
  local profile="$1"
  local p
  p="$(awk -F= -v k="$profile" '$1==k{print substr($0,index($0,$2))}' "$AUTH_MAP_FILE" | tail -n1)"
  echo "$p"
}

resolved=()
unresolved=()
manual_cmds=()

for profile in "${FAILED[@]}"; do
  short="${profile#${PROVIDER}:}"
  auth_path="$(lookup_auth_path "$profile")"
  ok=0

  if [[ -n "$auth_path" && -f "$auth_path" ]]; then
    if "$BASE_DIR/scripts/import_codex_auth_to_openclaw.sh" "$profile" main "$auth_path" >/dev/null 2>&1; then
      resolved+=("$profile")
      ok=1
    fi
  fi

  if [[ "$ok" -eq 0 ]]; then
    unresolved+=("$profile")
    manual_cmds+=("$short: codex logout && codex -c cli_auth_credentials_store='file' login --device-auth && $BASE_DIR/scripts/import_codex_auth_to_openclaw.sh $profile main $CODEX_AUTH_PATH")
    if [[ "$SUGGEST_DECOMMISSION" == "1" ]]; then
      manual_cmds+=("$short(封禁/失效不可恢复): $BASE_DIR/scripts/decommission_openai_codex_profile.sh $profile banned && # 然后添加新账号并导入")
    fi
  fi
done

# Always sync order after repair attempt
if [[ -x "$BASE_DIR/scripts/sync_openclaw_auth_order.sh" ]]; then
  "$BASE_DIR/scripts/sync_openclaw_auth_order.sh" "$PROVIDER" main >/dev/null 2>&1 || true
fi

# Optional gateway restart (usually unnecessary)
if [[ "$DO_RESTART_GATEWAY" == "1" ]]; then
  systemctl restart openclaw-gateway || true
fi

OUT_JSON="$BASE_DIR/reports/openai_codex_repair_latest.json"
OUT_JSON="$OUT_JSON" RESOLVED="$(printf '%s\n' "${resolved[@]:-}")" UNRESOLVED="$(printf '%s\n' "${unresolved[@]:-}")" MANUAL="$(printf '%s\n' "${manual_cmds[@]:-}")" node - <<'NODE'
const fs=require('fs');
const split=(s)=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const out={
  ts:new Date().toISOString(),
  resolvedProfiles:split(process.env.RESOLVED),
  unresolvedProfiles:split(process.env.UNRESOLVED),
  manualCommands:split(process.env.MANUAL)
};
fs.writeFileSync(process.env.OUT_JSON, JSON.stringify(out,null,2));
NODE

echo "repair summary"
echo "resolved: ${resolved[*]:-none}"
echo "unresolved: ${unresolved[*]:-none}"
echo "report: $OUT_JSON"

if [[ "$DO_NOTIFY" == "1" ]]; then
  msg="🛠️ openai-codex 修复结果\n已修复：${#resolved[@]}\n未修复：${#unresolved[@]}\n报告：$OUT_JSON"
  openclaw message send --channel "$TELEGRAM_CHANNEL" --target "$TELEGRAM_TARGET" --message "$msg" >/dev/null 2>&1 || true
fi

if ((${#unresolved[@]}>0)); then
  printf '%s\n' "${manual_cmds[@]}"
  exit 1
fi

exit 0
