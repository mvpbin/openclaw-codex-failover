#!/usr/bin/env bash
set -euo pipefail

# ========= Config (override via env) =========
BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
REPORT_DIR="${OCX_REPORT_DIR:-$BASE_DIR/reports}"
PROVIDER="${OCX_PROVIDER:-openai-codex}"
PROFILE_PREFIX="${OCX_PROFILE_PREFIX:-openai-codex:}"
MIN_PROFILES="${OCX_MIN_PROFILES:-1}"                 # hard check (< MIN => CRITICAL)
RECOMMENDED_MIN="${OCX_RECOMMENDED_MIN:-5}"          # soft recommendation
RECOMMENDED_MAX="${OCX_RECOMMENDED_MAX:-12}"         # soft recommendation
EXPIRING_HOURS="${OCX_EXPIRING_HOURS:-24}"           # remainingMs below this => WARN
TELEGRAM_CHANNEL="${OCX_NOTIFY_CHANNEL:-telegram}"
TELEGRAM_TARGET="${OCX_NOTIFY_TARGET:-182211955}"
OPENCLAW_AGENT_TIMEOUT="${OCX_AGENT_TIMEOUT_SECONDS:-45}"

mkdir -p "$REPORT_DIR"
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

log(){ echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }

status_json="$(openclaw models status --json 2>/dev/null || true)"
if [[ -z "$status_json" ]]; then
  CRITICALS+=("openclaw models status --json failed")
fi

# parse with node (no jq dependency)
parsed_json="$(STATUS_JSON="$status_json" PROVIDER="$PROVIDER" PREFIX="$PROFILE_PREFIX" node - <<'NODE'
const raw = process.env.STATUS_JSON || '{}';
const providerName = process.env.PROVIDER || 'openai-codex';
const prefix = process.env.PREFIX || 'openai-codex:';
let obj = {};
try { obj = JSON.parse(raw); } catch {}
const provider = (obj.auth?.providers || []).find(p => p.provider === providerName) || {};
const profiles = (obj.auth?.oauth?.profiles || []).filter(p => p.provider === providerName);
const unusableRaw = Array.isArray(obj.auth?.unusableProfiles) ? obj.auth.unusableProfiles : [];
const unusable = unusableRaw
  .map(x => (typeof x === 'string' ? x : x?.profileId))
  .filter(x => String(x || '').startsWith(prefix));
const pwo = Array.isArray(obj.auth?.providersWithOAuth) ? obj.auth.providersWithOAuth : [];
console.log(JSON.stringify({
  providersWithOAuth: pwo,
  providerProfileCount: Number(provider?.profiles?.count || 0),
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
if ! echo "$providers_with_oauth" | grep -qi "^${PROVIDER}$"; then
  CRITICALS+=("providersWithOAuth missing ${PROVIDER}")
fi

profile_count="$(PARSED="$parsed_json" node - <<'NODE'
const d=JSON.parse(process.env.PARSED||'{}');
console.log(Number(d.providerProfileCount||0));
NODE
)"
if (( profile_count < MIN_PROFILES )); then
  CRITICALS+=("${PROVIDER} profiles count < ${MIN_PROFILES}")
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

EXPIRING_MS=$((EXPIRING_HOURS * 3600000))
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid="${line%%$'\t'*}"
  rem="${line##*$'\t'}"
  ALL_PROFILES+=("$pid")
  if [[ "$rem" =~ ^-?[0-9]+$ ]]; then
    if (( rem < 0 )); then
      FAILED_PROFILES+=("$pid")
    elif (( rem < EXPIRING_MS )); then
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

# soft recommendation: profile count band
if (( ${#ALL_PROFILES[@]} < RECOMMENDED_MIN )); then
  WARNINGS+=("profile count below recommendation: ${#ALL_PROFILES[@]} < ${RECOMMENDED_MIN}")
elif (( ${#ALL_PROFILES[@]} > RECOMMENDED_MAX )); then
  WARNINGS+=("profile count above recommendation: ${#ALL_PROFILES[@]} > ${RECOMMENDED_MAX} (maintenance cost may rise)")
fi

# unique failed profiles
if ((${#FAILED_PROFILES[@]} > 0)); then
  mapfile -t FAILED_PROFILES < <(printf '%s\n' "${FAILED_PROFILES[@]}" | awk 'NF' | sort -u)
fi

# lightweight model call
hc_sid="healthcheck-$(date -u +%Y%m%dT%H%M%SZ)"
agent_out="$(timeout "$OPENCLAW_AGENT_TIMEOUT" openclaw agent --session-id "$hc_sid" --message "Reply exactly: ok" --thinking off --json 2>&1 || true)"
if ! echo "$agent_out" | grep -Eq '"text"\s*:\s*"ok"'; then
  CRITICALS+=("lightweight call failed")
  err_summary="$(echo "$agent_out" | tr '\n' ' ' | sed -E 's/[A-Za-z0-9_\-]{24,}/[REDACTED]/g' | cut -c1-300)"
else
  err_summary=""
fi

# relogin commands for failed profiles only
for f in "${FAILED_PROFILES[@]:-}"; do
  [[ -z "$f" ]] && continue
  short="${f#${PROFILE_PREFIX}}"
  [[ "$short" == "$f" ]] && short="$f"
  RELOGIN_CMDS+=("$short: codex logout && codex -c cli_auth_credentials_store='file' login --device-auth && /data/openclaw/scripts/import_codex_auth_to_openclaw.sh $f main /home/rdpuser/.codex/auth.json")
done

# sync auth order (best-effort)
sync_note=""
if [[ -x /data/openclaw/scripts/sync_openclaw_auth_order.sh ]]; then
  if /data/openclaw/scripts/sync_openclaw_auth_order.sh "$PROVIDER" main >/dev/null 2>&1; then
    sync_note="sync_openclaw_auth_order: ok"
  else
    sync_note="sync_openclaw_auth_order: failed"
    WARNINGS+=("sync_openclaw_auth_order failed")
  fi
else
  sync_note="sync script missing"
  WARNINGS+=("sync_openclaw_auth_order.sh missing")
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
PROVIDER="$PROVIDER" \
PROFILE_COUNT="$profile_count" \
EXIT_CODE="$exit_code" \
SYNC_NOTE="$sync_note" \
AGENT_ERR="$err_summary" \
REC_MIN="$RECOMMENDED_MIN" \
REC_MAX="$RECOMMENDED_MAX" \
ALL_PROFILES_JOINED="$(printf '%s\n' "${ALL_PROFILES[@]:-}")" \
FAILED_JOINED="$(printf '%s\n' "${FAILED_PROFILES[@]:-}")" \
WARN_JOINED="$(printf '%s\n' "${WARNINGS[@]:-}")" \
CRIT_JOINED="$(printf '%s\n' "${CRITICALS[@]:-}")" \
EXP_JOINED="$(printf '%s\n' "${EXPIRING_PROFILES[@]:-}")" \
RELOGIN_JOINED="$(printf '%s\n' "${RELOGIN_CMDS[@]:-}")" \
node - <<'NODE'
const fs=require('fs');
const split=(s)=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const report={
  ts: process.env.TS_UTC,
  provider: process.env.PROVIDER,
  discoveredProfiles: split(process.env.ALL_PROFILES_JOINED),
  discoveredCount: Number(process.env.PROFILE_COUNT||0),
  recommendations: {
    accountCount: `建议 ${process.env.REC_MIN}-${process.env.REC_MAX} 个账号池（过少影响容灾，过多增加维护成本）`
  },
  failedProfiles: split(process.env.FAILED_JOINED),
  expiringProfiles: split(process.env.EXP_JOINED),
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
log "${PROVIDER} health summary"
log "profiles discovered: ${#ALL_PROFILES[@]}"
log "failed profiles: ${FAILED_PROFILES[*]:-none}"
log "warnings: ${WARNINGS[*]:-none}"
log "criticals: ${CRITICALS[*]:-none}"
log "sync: $sync_note"
log "report: $LATEST_JSON"

# telegram summary (single message, avoid duplicates)
level="PASS"
if [[ "$exit_code" -eq 2 ]]; then
  level="CRITICAL"
elif [[ "$exit_code" -eq 1 ]]; then
  level="WARN"
fi
failed_csv="$(printf '%s, ' "${FAILED_PROFILES[@]:-}" | sed 's/, $//')"
[[ -z "$failed_csv" ]] && failed_csv="none"
if [[ "$level" == "PASS" ]]; then
  icon="✅"; level_cn="健康"
elif [[ "$level" == "WARN" ]]; then
  icon="⚠️"; level_cn="预警"
else
  icon="🚨"; level_cn="严重"
fi

action_line="无"
if ((${#RELOGIN_CMDS[@]} > 0)); then
  action_line="请仅重登失效账号（见报告 reloginCommands）"
fi
msg="${icon} OpenClaw 每日健康检查（${PROVIDER}）\n状态：${level_cn} (${level})\n账号数：${#ALL_PROFILES[@]}（建议 ${RECOMMENDED_MIN}-${RECOMMENDED_MAX}）\n失效账号：${failed_csv}\n处理建议：${action_line}\n报告：${LATEST_JSON}"
openclaw message send --channel "$TELEGRAM_CHANNEL" --target "$TELEGRAM_TARGET" --message "$msg" >/dev/null 2>&1 || true

exit "$exit_code"
