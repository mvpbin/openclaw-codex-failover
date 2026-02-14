#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/data/openclaw"
SCRIPTS_DIR="$BASE_DIR/scripts"
REPORT_DIR="$BASE_DIR/reports"
mkdir -p "$SCRIPTS_DIR" "$REPORT_DIR"

DATE_UTC="$(date -u +%Y%m%d)"
TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_FILE="$REPORT_DIR/openai_codex_health_${DATE_UTC}.log"
LATEST_JSON="$REPORT_DIR/openai_codex_health_latest.json"

WARNINGS=()
CRITICALS=()
RELOGIN_CMDS=()
FAILED_PROFILES=()
EXPIRING_PROFILES=()
ALL_PROFILES=()
UNUSABLE_PROFILES=()

SIMULATE_UNUSABLE="${SIMULATE_UNUSABLE:-}"
if [[ "${1:-}" == "--simulate-unusable" ]]; then
  SIMULATE_UNUSABLE="${2:-}"
fi

EXPECTED=("openai-codex:acc01" "openai-codex:acc02" "openai-codex:acc03" "openai-codex:acc04" "openai-codex:acc05")

log(){ echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }

status_json="$(openclaw models status --json 2>/dev/null || true)"
if [[ -z "$status_json" ]]; then
  CRITICALS+=("openclaw models status --json failed")
fi

# parse with node (no jq dependency)
parsed_json="$(STATUS_JSON="$status_json" node - <<'NODE'
const raw = process.env.STATUS_JSON || '{}';
let obj = {};
try { obj = JSON.parse(raw); } catch {}
const provider = (obj.auth?.providers || []).find(p => p.provider === 'openai-codex') || {};
const profiles = (obj.auth?.oauth?.profiles || []).filter(p => p.provider === 'openai-codex');
const unusable = Array.isArray(obj.auth?.unusableProfiles)
  ? obj.auth.unusableProfiles
      .map(x => (typeof x === 'string' ? x : x?.profileId))
      .filter(x => String(x || '').startsWith('openai-codex:'))
  : [];
const pwo = Array.isArray(obj.auth?.providersWithOAuth) ? obj.auth.providersWithOAuth : [];
console.log(JSON.stringify({
  providersWithOAuth: pwo,
  openaiCodexProfileCount: Number(provider?.profiles?.count || 0),
  oauthProfiles: profiles,
  unusableProfiles: unusable
}));
NODE
)"

providers_with_oauth="$(PARSED="$parsed_json" node - <<'NODE'
const d=JSON.parse(process.env.PARSED||'{}');
console.log((d.providersWithOAuth||[]).join('\n'));
NODE
)"
if ! echo "$providers_with_oauth" | grep -qi '^openai-codex'; then
  CRITICALS+=("providersWithOAuth missing openai-codex")
fi

profile_count="$(PARSED="$parsed_json" node - <<'NODE'
const d=JSON.parse(process.env.PARSED||'{}');
console.log(Number(d.openaiCodexProfileCount||0));
NODE
)"
if [[ "$profile_count" -lt 1 ]]; then
  CRITICALS+=("openai-codex profiles count < 1")
fi

while IFS= read -r p; do
  [[ -n "$p" ]] && UNUSABLE_PROFILES+=("$p")
done < <(PARSED="$parsed_json" node - <<'NODE'
const d=JSON.parse(process.env.PARSED||'{}');
for (const p of (d.unusableProfiles||[])) console.log(p);
NODE
)

if [[ -n "$SIMULATE_UNUSABLE" ]]; then
  UNUSABLE_PROFILES+=("$SIMULATE_UNUSABLE")
  WARNINGS+=("simulation enabled for $SIMULATE_UNUSABLE")
fi

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # profileId\tremainingMs
  pid="${line%%$'\t'*}"
  rem="${line##*$'\t'}"
  ALL_PROFILES+=("$pid")
  if [[ "$rem" =~ ^-?[0-9]+$ ]]; then
    if (( rem < 0 )); then
      FAILED_PROFILES+=("$pid")
    elif (( rem < 86400000 )); then
      EXPIRING_PROFILES+=("$pid:$rem")
    fi
  fi
done < <(PARSED="$parsed_json" node - <<'NODE'
const d=JSON.parse(process.env.PARSED||'{}');
for (const p of (d.oauthProfiles||[])) {
  console.log(`${p.profileId}\t${Number(p.remainingMs||0)}`)
}
NODE
)

for u in "${UNUSABLE_PROFILES[@]:-}"; do
  [[ -n "$u" ]] && FAILED_PROFILES+=("$u")
done

# expected 5 account presence check
for e in "${EXPECTED[@]}"; do
  found=0
  for a in "${ALL_PROFILES[@]:-}"; do
    [[ "$a" == "$e" ]] && found=1 && break
  done
  if [[ $found -eq 0 ]]; then
    WARNINGS+=("missing expected profile: $e")
  fi
done

# unique failed profiles
if ((${#FAILED_PROFILES[@]} > 0)); then
  mapfile -t FAILED_PROFILES < <(printf '%s\n' "${FAILED_PROFILES[@]}" | awk 'NF' | sort -u)
fi

# lightweight model call
hc_sid="healthcheck-$(date -u +%Y%m%dT%H%M%SZ)"
agent_out="$(openclaw agent --session-id "$hc_sid" --message "Reply exactly: ok" --thinking off --json 2>&1 || true)"
if ! echo "$agent_out" | grep -Eq '"text"\s*:\s*"ok"'; then
  CRITICALS+=("lightweight call failed")
  # short sanitized summary
  err_summary="$(echo "$agent_out" | tr '\n' ' ' | sed -E 's/[A-Za-z0-9_\-]{24,}/[REDACTED]/g' | cut -c1-300)"
else
  err_summary=""
fi

# relogin commands for failed accXX only
for f in "${FAILED_PROFILES[@]}"; do
  short="${f#openai-codex:}"
  [[ "$short" == "$f" ]] && short="$f"
  RELOGIN_CMDS+=("$short: codex logout && codex -c cli_auth_credentials_store='file' login --device-auth && /data/openclaw/scripts/import_codex_auth_to_openclaw.sh $f main /home/rdpuser/.codex/auth.json")
done

# sync auth order (best-effort)
sync_note=""
if [[ -x /data/openclaw/scripts/sync_openclaw_auth_order.sh ]]; then
  if /data/openclaw/scripts/sync_openclaw_auth_order.sh openai-codex main >/dev/null 2>&1; then
    sync_note="sync_openclaw_auth_order: ok"
  else
    sync_note="sync_openclaw_auth_order: failed"
    WARNINGS+=("sync_openclaw_auth_order failed")
  fi
else
  sync_note="sync script missing"
  WARNINGS+=("sync_openclaw_auth_order.sh missing")
fi

# telegram alert (best-effort)
send_alert(){
  local lvl="$1"; shift
  local msg="$*"
  openclaw message send --channel telegram --target 182211955 --message "$msg" >/dev/null 2>&1 || true
}

if ((${#CRITICALS[@]} > 0)); then
  failed_csv="$(printf '%s, ' "${FAILED_PROFILES[@]:-}" | sed 's/, $//')"
  [[ -z "$failed_csv" ]] && failed_csv="unknown"
  send_alert CRITICAL "[CRITICAL] openai-codex pool unhealthy - failed profiles: $failed_csv - action: re-login specific accounts"
elif ((${#EXPIRING_PROFILES[@]} > 0)); then
  pretty="$(for x in "${EXPIRING_PROFILES[@]}"; do p="${x%%:*}"; ms="${x##*:}"; h=$((ms/3600000)); echo -n "${p#openai-codex:}(in ${h}h), "; done | sed 's/, $//')"
  send_alert WARN "[WARN] expiring soon: $pretty"
fi

# determine exit
exit_code=0
if ((${#CRITICALS[@]} > 0)); then
  exit_code=2
elif ((${#WARNINGS[@]} > 0 || ${#EXPIRING_PROFILES[@]} > 0)); then
  exit_code=1
fi

# report json
REPORT_JSON="$LATEST_JSON" \
TS_UTC="$TS_UTC" \
PROFILE_COUNT="$profile_count" \
EXIT_CODE="$exit_code" \
SYNC_NOTE="$sync_note" \
AGENT_ERR="$err_summary" \
ALL_PROFILES_JOINED="$(printf '%s\n' "${ALL_PROFILES[@]:-}")" \
FAILED_JOINED="$(printf '%s\n' "${FAILED_PROFILES[@]:-}")" \
WARN_JOINED="$(printf '%s\n' "${WARNINGS[@]:-}")" \
CRIT_JOINED="$(printf '%s\n' "${CRITICALS[@]:-}")" \
RELOGIN_JOINED="$(printf '%s\n' "${RELOGIN_CMDS[@]:-}")" \
node - <<'NODE'
const fs=require('fs');
const split=(s)=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const report={
  ts: process.env.TS_UTC,
  provider: 'openai-codex',
  expectedProfiles: ['openai-codex:acc01','openai-codex:acc02','openai-codex:acc03','openai-codex:acc04','openai-codex:acc05'],
  discoveredProfiles: split(process.env.ALL_PROFILES_JOINED),
  discoveredCount: Number(process.env.PROFILE_COUNT||0),
  failedProfiles: split(process.env.FAILED_JOINED),
  warnings: split(process.env.WARN_JOINED),
  criticals: split(process.env.CRIT_JOINED),
  reloginCommands: split(process.env.RELOGIN_JOINED),
  lightweightCallErrorSummary: process.env.AGENT_ERR || '',
  syncNote: process.env.SYNC_NOTE || '',
  gatewayRestartNeeded: false,
  exitCode: Number(process.env.EXIT_CODE||0)
};
fs.writeFileSync(process.env.REPORT_JSON, JSON.stringify(report,null,2));
NODE

# terminal summary
log "openai-codex health summary"
log "profiles discovered: ${#ALL_PROFILES[@]} | expected: 5"
log "failed profiles: ${FAILED_PROFILES[*]:-none}"
log "warnings: ${WARNINGS[*]:-none}"
log "criticals: ${CRITICALS[*]:-none}"
log "sync: $sync_note"
log "report: $LATEST_JSON"

# always-on telegram summary (PASS/WARN/CRITICAL)
level="PASS"
if [[ "$exit_code" -eq 2 ]]; then
  level="CRITICAL"
elif [[ "$exit_code" -eq 1 ]]; then
  level="WARN"
fi
failed_csv="$(printf '%s, ' "${FAILED_PROFILES[@]:-}" | sed 's/, $//')"
[[ -z "$failed_csv" ]] && failed_csv="none"
if [[ "$level" == "PASS" ]]; then
  icon="✅"
  level_cn="健康"
elif [[ "$level" == "WARN" ]]; then
  icon="⚠️"
  level_cn="预警"
else
  icon="🚨"
  level_cn="严重"
fi
msg="${icon} OpenClaw 每日健康检查（openai-codex）\n状态：${level_cn} (${level})\n账号：${#ALL_PROFILES[@]}/5\n失效账号：${failed_csv}\n报告：${LATEST_JSON}"
openclaw message send --channel telegram --target 182211955 --message "$msg" >/dev/null 2>&1 || true

exit "$exit_code"
