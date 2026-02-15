#!/usr/bin/env bash
set -euo pipefail

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
REPORT_DIR="${OCX_REPORT_DIR:-$BASE_DIR/reports}"
RUN_DIR="${OCX_RUN_DIR:-$BASE_DIR/run}"
PROVIDER="${OCX_PROVIDER:-openai-codex}"
PROFILE_PREFIX="${OCX_PROFILE_PREFIX:-openai-codex:}"
MIN_PROFILES="${OCX_MIN_PROFILES:-1}"
RECOMMENDED_MIN="${OCX_RECOMMENDED_MIN:-5}"
RECOMMENDED_MAX="${OCX_RECOMMENDED_MAX:-12}"
EXPIRING_HOURS="${OCX_EXPIRING_HOURS:-24}"
TELEGRAM_CHANNEL="${OCX_NOTIFY_CHANNEL:-telegram}"
TELEGRAM_TARGET="${OCX_NOTIFY_TARGET:-182211955}"
OPENCLAW_AGENT_TIMEOUT="${OCX_AGENT_TIMEOUT_SECONDS:-45}"
LOG_RETENTION_DAYS="${OCX_LOG_RETENTION_DAYS:-30}"
LOCK_FILE="${OCX_LOCK_FILE:-$RUN_DIR/openai_codex_healthcheck.lock}"
ALERT_STATE_FILE="${OCX_ALERT_STATE_FILE:-$RUN_DIR/openai_codex_alert_state.json}"
POOL_STATE_FILE="${OCX_POOL_STATE_FILE:-$RUN_DIR/openai_codex_pool_state.json}"
SLO_FILE="${OCX_SLO_FILE:-$REPORT_DIR/openai_codex_slo_metrics.json}"
CONFIG_HISTORY_DIR="${OCX_CONFIG_HISTORY_DIR:-$BASE_DIR/config/history}"
ALERT_BURST_COUNT="${OCX_ALERT_BURST_COUNT:-3}"
ALERT_REMIND_SECONDS="${OCX_ALERT_REMIND_SECONDS:-3600}"
ALERT_DEDUP_SECONDS="${OCX_ALERT_DEDUP_SECONDS:-900}"
AUTO_REPAIR="${OCX_AUTO_REPAIR:-0}"
REPAIR_MIN_INTERVAL="${OCX_REPAIR_MIN_INTERVAL_SECONDS:-1800}"
AUTO_REORDER="${OCX_AUTO_REORDER:-0}"
CB_FAIL_THRESHOLD="${OCX_CB_FAIL_THRESHOLD:-3}"
CB_COOLDOWN_SECONDS="${OCX_CB_COOLDOWN_SECONDS:-3600}"
DRY_RUN="${OCX_DRY_RUN:-0}"

mkdir -p "$REPORT_DIR" "$RUN_DIR" "$CONFIG_HISTORY_DIR"
DATE_UTC="$(date -u +%Y%m%d)"
TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_TS="$(date +%s)"
LOG_FILE="$REPORT_DIR/openai_codex_health_${DATE_UTC}.log"
LATEST_JSON="$REPORT_DIR/openai_codex_health_latest.json"

WARNINGS=(); CRITICALS=(); RELOGIN_CMDS=(); FAILED_PROFILES=(); EXPIRING_PROFILES=(); ALL_PROFILES=(); UNUSABLE_PROFILES=(); COOLDOWN_PROFILES=();
declare -A PROFILE_EMAIL_MAP PROFILE_REMAINING PROFILE_SCORE PROFILE_FAILCOUNT PROFILE_COOLDOWN_UNTIL

SIMULATE_UNUSABLE="${SIMULATE_UNUSABLE:-}"
[[ "${1:-}" == "--simulate-unusable" ]] && SIMULATE_UNUSABLE="${2:-}"
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

log(){ echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }
mask_email(){ local e="$1"; [[ "$e" == *"@"* ]] && { local n="${e%@*}" d="${e#*@}"; [[ ${#n} -gt 1 ]] && echo "${n:0:1}***@${d}" || echo "***@${d}"; } || echo "$e"; }
profile_display(){ local p="$1" e="${PROFILE_EMAIL_MAP[$p]:-}"; [[ -n "$e" ]] && echo "${p#${PROFILE_PREFIX}}($(mask_email "$e"))" || echo "${p#${PROFILE_PREFIX}}"; }

# lock
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "another healthcheck is running, skip"
  exit 1
fi

# retention + config snapshot versioning
find "$REPORT_DIR" -maxdepth 1 -type f -name 'openai_codex_health_*.log' -mtime "+$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  cfg_hash="$(sha256sum "$DEFAULT_ENV_FILE" | awk '{print $1}')"
  state_hash=""
  [[ -f "$RUN_DIR/openai_codex_config_hash.txt" ]] && state_hash="$(cat "$RUN_DIR/openai_codex_config_hash.txt" 2>/dev/null || true)"
  if [[ "$cfg_hash" != "$state_hash" ]]; then
    cp "$DEFAULT_ENV_FILE" "$CONFIG_HISTORY_DIR/openclaw-healthcheck.$(date -u +%Y%m%dT%H%M%SZ).env"
    echo "$cfg_hash" > "$RUN_DIR/openai_codex_config_hash.txt"
  fi
fi

# load persistent pool state
if [[ -f "$POOL_STATE_FILE" ]]; then
  while IFS=$'\t' read -r k fail cooldown; do
    [[ -n "$k" ]] || continue
    PROFILE_FAILCOUNT["$k"]="${fail:-0}"
    PROFILE_COOLDOWN_UNTIL["$k"]="${cooldown:-0}"
  done < <(STATE="$POOL_STATE_FILE" node - <<'NODE'
const fs=require('fs');
try{
  const s=JSON.parse(fs.readFileSync(process.env.STATE,'utf8'));
  const p=s.profiles||{};
  for(const k of Object.keys(p)) console.log(`${k}\t${Number(p[k].failCount||0)}\t${Number(p[k].cooldownUntil||0)}`);
}catch{}
NODE
)
fi

status_json="$(openclaw models status --json 2>/dev/null || true)"
if [[ -z "$status_json" ]]; then CRITICALS+=("openclaw models status --json failed"); fi

parsed_json="$(STATUS_JSON="$status_json" PROVIDER="$PROVIDER" PREFIX="$PROFILE_PREFIX" node - <<'NODE'
const raw=process.env.STATUS_JSON||'{}'; const providerName=process.env.PROVIDER||'openai-codex'; const prefix=process.env.PREFIX||'openai-codex:';
let obj={}; try{obj=JSON.parse(raw);}catch{}
const provider=(obj.auth?.providers||[]).find(p=>p.provider===providerName)||{};
const profiles=(obj.auth?.oauth?.profiles||[]).filter(p=>p.provider===providerName);
const unusable=(Array.isArray(obj.auth?.unusableProfiles)?obj.auth.unusableProfiles:[]).map(x=>typeof x==='string'?x:x?.profileId).filter(x=>String(x||'').startsWith(prefix));
const labels=provider?.profiles?.labels||[];
console.log(JSON.stringify({providersWithOAuth:obj.auth?.providersWithOAuth||[],providerProfileCount:Number(provider?.profiles?.count||0),oauthProfiles:profiles,unusableProfiles:unusable,labels}));
NODE
)"

providers_with_oauth="$(PARSED="$parsed_json" node -e "const d=JSON.parse(process.env.PARSED||'{}');console.log((d.providersWithOAuth||[]).join('\\n'));" )"
if ! echo "$providers_with_oauth" | grep -qi "^${PROVIDER}"; then CRITICALS+=("providersWithOAuth missing ${PROVIDER}"); fi

profile_count="$(PARSED="$parsed_json" node -e "const d=JSON.parse(process.env.PARSED||'{}');console.log(Number(d.providerProfileCount||0));")"
if (( profile_count < MIN_PROFILES )); then CRITICALS+=("${PROVIDER} profiles count < ${MIN_PROFILES}"); fi

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid="${line%%$'\t'*}"; email="${line##*$'\t'}"
  [[ -n "$pid" && -n "$email" && "$email" == *"@"* ]] && PROFILE_EMAIL_MAP["$pid"]="$email"
done < <(PARSED="$parsed_json" node - <<'NODE'
const d=JSON.parse(process.env.PARSED||'{}');
for(const l of (d.labels||[])){ const s=String(l||''); const i=s.indexOf('='); if(i>0){const id=s.slice(0,i).trim(); const em=s.slice(i+1).trim(); if(id&&em.includes('@')) console.log(`${id}\t${em}`);} }
NODE
)

while IFS= read -r p; do [[ -n "$p" ]] && UNUSABLE_PROFILES+=("$p"); done < <(PARSED="$parsed_json" node -e "const d=JSON.parse(process.env.PARSED||'{}');for(const p of (d.unusableProfiles||[])) console.log(p)")
[[ -n "$SIMULATE_UNUSABLE" ]] && { UNUSABLE_PROFILES+=("$SIMULATE_UNUSABLE"); WARNINGS+=("simulation enabled for $SIMULATE_UNUSABLE"); }

EXPIRING_MS=$((EXPIRING_HOURS*3600000))
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  pid="${line%%$'\t'*}"; rem="${line##*$'\t'}"
  ALL_PROFILES+=("$pid"); PROFILE_REMAINING["$pid"]="$rem"
  cooldown_until="${PROFILE_COOLDOWN_UNTIL[$pid]:-0}"
  if (( cooldown_until > NOW_TS )); then
    COOLDOWN_PROFILES+=("$pid")
    WARNINGS+=("cooldown active: ${pid#${PROFILE_PREFIX}} until $(date -u -d @${cooldown_until} +%H:%M:%S 2>/dev/null || echo ${cooldown_until})")
    continue
  fi
  if [[ "$rem" =~ ^-?[0-9]+$ ]]; then
    if (( rem < 0 )); then FAILED_PROFILES+=("$pid")
    elif (( rem < EXPIRING_MS )); then EXPIRING_PROFILES+=("$pid:$rem")
    fi
  fi
done < <(PARSED="$parsed_json" node - <<'NODE'
const d=JSON.parse(process.env.PARSED||'{}');
for(const p of (d.oauthProfiles||[])) console.log(`${p.profileId}\t${Number(p.remainingMs||0)}`);
NODE
)

for u in "${UNUSABLE_PROFILES[@]:-}"; do [[ -n "$u" ]] && FAILED_PROFILES+=("$u"); done
if ((${#FAILED_PROFILES[@]} > 0)); then mapfile -t FAILED_PROFILES < <(printf '%s\n' "${FAILED_PROFILES[@]}" | awk 'NF' | sort -u); fi

# scoring + circuit breaker counters
for p in "${ALL_PROFILES[@]:-}"; do
  rem="${PROFILE_REMAINING[$p]:-0}"; fail="${PROFILE_FAILCOUNT[$p]:-0}"; score=100
  if [[ "$rem" =~ ^-?[0-9]+$ ]]; then
    (( rem < 0 )) && score=$((score-80))
    (( rem >=0 && rem < EXPIRING_MS )) && score=$((score-30))
  fi
  score=$((score - fail*15)); (( score < 0 )) && score=0
  PROFILE_SCORE["$p"]="$score"

done

for f in "${FAILED_PROFILES[@]:-}"; do
  [[ -z "$f" ]] && continue
  cur="${PROFILE_FAILCOUNT[$f]:-0}"; cur=$((cur+1)); PROFILE_FAILCOUNT["$f"]="$cur"
  if (( cur >= CB_FAIL_THRESHOLD )); then
    PROFILE_COOLDOWN_UNTIL["$f"]=$((NOW_TS + CB_COOLDOWN_SECONDS))
    WARNINGS+=("circuit breaker tripped: ${f#${PROFILE_PREFIX}} for ${CB_COOLDOWN_SECONDS}s")
  fi
  short="${f#${PROFILE_PREFIX}}"
  RELOGIN_CMDS+=("$short: codex logout && codex -c cli_auth_credentials_store='file' login --device-auth && $BASE_DIR/scripts/import_codex_auth_to_openclaw.sh $f main /home/rdpuser/.codex/auth.json")
done

# reset fail count for healthy profiles
for p in "${ALL_PROFILES[@]:-}"; do
  bad=0; for f in "${FAILED_PROFILES[@]:-}"; do [[ "$p" == "$f" ]] && bad=1; done
  (( bad==0 )) && PROFILE_FAILCOUNT["$p"]=0
done

# recommendations
if (( ${#ALL_PROFILES[@]} < RECOMMENDED_MIN )); then WARNINGS+=("profile count below recommendation: ${#ALL_PROFILES[@]} < ${RECOMMENDED_MIN}"); fi
if (( ${#ALL_PROFILES[@]} > RECOMMENDED_MAX )); then WARNINGS+=("profile count above recommendation: ${#ALL_PROFILES[@]} > ${RECOMMENDED_MAX}"); fi

# multi-probe
probe1_out="$(timeout "$OPENCLAW_AGENT_TIMEOUT" openclaw agent --session-id "healthcheck-$(date -u +%Y%m%dT%H%M%SZ)-a" --message "Reply exactly: ok" --thinking off --json 2>&1 || true)"
probe2_out="$(timeout "$OPENCLAW_AGENT_TIMEOUT" openclaw agent --session-id "healthcheck-$(date -u +%Y%m%dT%H%M%SZ)-b" --message "Reply exactly: pong" --thinking off --json 2>&1 || true)"
probe1_ok=0; probe2_ok=0
echo "$probe1_out" | grep -Eq '"text"\s*:\s*"ok"' && probe1_ok=1
echo "$probe2_out" | grep -Eq '"text"\s*:\s*"pong"' && probe2_ok=1
if (( probe1_ok==0 && probe2_ok==0 )); then
  CRITICALS+=("both probes failed")
elif (( probe1_ok==0 || probe2_ok==0 )); then
  WARNINGS+=("one probe failed")
fi
err_summary=""
if (( probe1_ok==0 || probe2_ok==0 )); then
  err_summary="$(echo "$probe1_out | $probe2_out" | tr '\n' ' ' | sed -E 's/[A-Za-z0-9_\-]{24,}/[REDACTED]/g' | cut -c1-300)"
fi

# anomaly classification
ANOMALY_CLASS="none"
classify(){
  local s="$1"
  if echo "$s" | grep -Eqi 'expired|invalid|oauth|accountId|relogin|banned'; then echo auth; return; fi
  if echo "$s" | grep -Eqi 'tls|curl|timeout|connect|dns|network'; then echo network; return; fi
  if echo "$s" | grep -Eqi 'probe|model|provider'; then echo provider; return; fi
  echo unknown
}
if ((${#CRITICALS[@]}+${#WARNINGS[@]} > 0)); then
  merged="$(printf '%s\n' "${CRITICALS[@]:-}" "${WARNINGS[@]:-}")"
  ANOMALY_CLASS="$(classify "$merged")"
fi

# compute state machine
state="Healthy"
if ((${#CRITICALS[@]} > 0)); then state="Degraded"; fi
if ((${#WARNINGS[@]} > 0 && ${#CRITICALS[@]}==0)); then state="Degraded"; fi
if [[ "$AUTO_REPAIR" == "1" && "$state" == "Degraded" && "$DRY_RUN" != "1" ]]; then state="Repairing"; fi

# auto reorder by health score
if [[ "$AUTO_REORDER" == "1" && ${#ALL_PROFILES[@]} -gt 0 ]]; then
  mapfile -t sorted_profiles < <(for p in "${ALL_PROFILES[@]}"; do echo -e "${PROFILE_SCORE[$p]:-0}\t$p"; done | sort -rn | awk '{print $2}')
  if ((${#sorted_profiles[@]} > 0)); then
    openclaw models auth order set --agent main --provider "$PROVIDER" "${sorted_profiles[@]}" >/dev/null 2>&1 || WARNINGS+=("auto reorder failed")
  fi
fi

# sync auth order always best effort
sync_note=""
if [[ -x "$BASE_DIR/scripts/sync_openclaw_auth_order.sh" ]]; then
  if "$BASE_DIR/scripts/sync_openclaw_auth_order.sh" "$PROVIDER" main >/dev/null 2>&1; then sync_note="sync_openclaw_auth_order: ok"; else sync_note="sync_openclaw_auth_order: failed"; WARNINGS+=("sync_openclaw_auth_order failed"); fi
else sync_note="sync script missing"; WARNINGS+=("sync script missing"); fi

# repair throttling
repair_attempted=0
if [[ "$AUTO_REPAIR" == "1" && "$state" == "Repairing" && "$DRY_RUN" != "1" ]]; then
  last_repair_ts=0
  [[ -f "$POOL_STATE_FILE" ]] && last_repair_ts="$(node -e "const fs=require('fs');try{const s=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(String(Number(s.lastRepairTs||0)));}catch{process.stdout.write('0')}" "$POOL_STATE_FILE")"
  if (( NOW_TS - last_repair_ts >= REPAIR_MIN_INTERVAL )); then
    if [[ -x "$BASE_DIR/scripts/repair_openai_codex_pool.sh" ]]; then
      "$BASE_DIR/scripts/repair_openai_codex_pool.sh" "$LATEST_JSON" >/dev/null 2>&1 || true
      repair_attempted=1
      WARNINGS+=("auto-repair attempted")
    else
      WARNINGS+=("auto-repair enabled but script missing")
    fi
  else
    WARNINGS+=("auto-repair throttled (${REPAIR_MIN_INTERVAL}s)")
  fi
fi

# exit code
exit_code=0
if ((${#CRITICALS[@]} > 0)); then exit_code=2; elif ((${#WARNINGS[@]} > 0 || ${#EXPIRING_PROFILES[@]} > 0)); then exit_code=1; fi
if (( exit_code==0 )); then state="Recovered"; fi

# persist pool state
POOL_STATE_FILE="$POOL_STATE_FILE" NOW_TS="$NOW_TS" STATE="$state" ANOMALY_CLASS="$ANOMALY_CLASS" REPAIR_ATTEMPTED="$repair_attempted" \
PROFILES_JOINED="$(for p in "${ALL_PROFILES[@]:-}"; do echo "$p|${PROFILE_FAILCOUNT[$p]:-0}|${PROFILE_COOLDOWN_UNTIL[$p]:-0}"; done)" node - <<'NODE'
const fs=require('fs');
const split=(s)=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const lines=split(process.env.PROFILES_JOINED);
let prev={}; try{prev=JSON.parse(fs.readFileSync(process.env.POOL_STATE_FILE,'utf8'));}catch{}
const profiles={};
for(const l of lines){const [k,f,c]=l.split('|'); if(k) profiles[k]={failCount:Number(f||0),cooldownUntil:Number(c||0)};}
const out={
  ts:new Date().toISOString(),
  state:process.env.STATE,
  anomalyClass:process.env.ANOMALY_CLASS,
  lastRepairTs: process.env.REPAIR_ATTEMPTED==='1'?Number(process.env.NOW_TS):Number(prev.lastRepairTs||0),
  profiles
};
fs.writeFileSync(process.env.POOL_STATE_FILE, JSON.stringify(out,null,2));
NODE

# write SLO metrics
SLO_FILE="$SLO_FILE" EXIT_CODE="$exit_code" NOW_TS="$NOW_TS" REPAIR_ATTEMPTED="$repair_attempted" node - <<'NODE'
const fs=require('fs');
let s={windowStart:Date.now(),runs:0,pass:0,warn:0,critical:0,repairAttempts:0};
try{s=Object.assign(s,JSON.parse(fs.readFileSync(process.env.SLO_FILE,'utf8')));}catch{}
s.runs+=1;
const e=Number(process.env.EXIT_CODE||0); if(e===0)s.pass+=1; else if(e===1)s.warn+=1; else s.critical+=1;
if(process.env.REPAIR_ATTEMPTED==='1') s.repairAttempts+=1;
s.lastRunTs=Number(process.env.NOW_TS||0);
fs.writeFileSync(process.env.SLO_FILE, JSON.stringify(s,null,2));
NODE

# report
REPORT_JSON="$LATEST_JSON" TS_UTC="$TS_UTC" PROVIDER="$PROVIDER" PROFILE_COUNT="$profile_count" EXIT_CODE="$exit_code" SYNC_NOTE="$sync_note" AGENT_ERR="$err_summary" REC_MIN="$RECOMMENDED_MIN" REC_MAX="$RECOMMENDED_MAX" STATE="$state" ANOMALY_CLASS="$ANOMALY_CLASS" \
ALL_PROFILES_JOINED="$(printf '%s\n' "${ALL_PROFILES[@]:-}")" FAILED_JOINED="$(printf '%s\n' "${FAILED_PROFILES[@]:-}")" WARN_JOINED="$(printf '%s\n' "${WARNINGS[@]:-}")" CRIT_JOINED="$(printf '%s\n' "${CRITICALS[@]:-}")" EXP_JOINED="$(printf '%s\n' "${EXPIRING_PROFILES[@]:-}")" RELOGIN_JOINED="$(printf '%s\n' "${RELOGIN_CMDS[@]:-}")" \
EMAIL_MAP_JOINED="$(for k in "${!PROFILE_EMAIL_MAP[@]}"; do echo "$k=${PROFILE_EMAIL_MAP[$k]}"; done)" SCORE_JOINED="$(for k in "${!PROFILE_SCORE[@]}"; do echo "$k=${PROFILE_SCORE[$k]}"; done)" DRY_RUN="$DRY_RUN" node - <<'NODE'
const fs=require('fs');
const split=s=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const mapFrom=(s)=>{const o={};for(const l of split(s)){const i=l.indexOf('=');if(i>0)o[l.slice(0,i).trim()]=l.slice(i+1).trim();}return o;};
const failed=split(process.env.FAILED_JOINED);
const emailMap=mapFrom(process.env.EMAIL_MAP_JOINED); const scoreMap=mapFrom(process.env.SCORE_JOINED);
const report={
  ts:process.env.TS_UTC,
  state:process.env.STATE,
  anomalyClass:process.env.ANOMALY_CLASS,
  provider:process.env.PROVIDER,
  discoveredProfiles:split(process.env.ALL_PROFILES_JOINED),
  discoveredCount:Number(process.env.PROFILE_COUNT||0),
  profileScores:scoreMap,
  recommendations:{accountCount:`建议 ${process.env.REC_MIN}-${process.env.REC_MAX} 个账号池（过少影响容灾，过多增加维护成本）`},
  failedProfiles:failed,
  failedProfilesWithEmail:failed.map(p=>({profileId:p,email:emailMap[p]||''})),
  expiringProfiles:split(process.env.EXP_JOINED),
  warnings:split(process.env.WARN_JOINED),
  criticals:split(process.env.CRIT_JOINED),
  reloginCommands:split(process.env.RELOGIN_JOINED),
  probeErrorSummary:process.env.AGENT_ERR||'',
  syncNote:process.env.SYNC_NOTE||'',
  dryRun:process.env.DRY_RUN==='1',
  exitCode:Number(process.env.EXIT_CODE||0)
};
fs.writeFileSync(process.env.REPORT_JSON, JSON.stringify(report,null,2));
NODE

log "${PROVIDER} health summary"
log "state: $state | class: $ANOMALY_CLASS"
log "profiles discovered: ${#ALL_PROFILES[@]}"
log "failed profiles: ${FAILED_PROFILES[*]:-none}"
log "warnings: ${WARNINGS[*]:-none}"
log "criticals: ${CRITICALS[*]:-none}"
log "sync: $sync_note"
log "report: $LATEST_JSON"

# alerting (dedup + burst + hourly remind)
if [[ "$DRY_RUN" != "1" ]]; then
  level="PASS"; ((exit_code==2)) && level="CRITICAL"; ((exit_code==1)) && level="WARN"
  failed_csv="none"
  if ((${#FAILED_PROFILES[@]} > 0)); then failed_csv=""; for fp in "${FAILED_PROFILES[@]}"; do failed_csv+="$(profile_display "$fp"), "; done; failed_csv="${failed_csv%, }"; fi
  reason="无"; ((${#CRITICALS[@]} > 0)) && reason="$(printf '%s; ' "${CRITICALS[@]}"|sed 's/; $//')"; ((${#CRITICALS[@]}==0 && ${#WARNINGS[@]}>0)) && reason="$(printf '%s; ' "${WARNINGS[@]}"|sed 's/; $//')"
  [[ "$level" == "PASS" ]] && icon="✅" && level_cn="健康"
  [[ "$level" == "WARN" ]] && icon="⚠️" && level_cn="预警"
  [[ "$level" == "CRITICAL" ]] && icon="🚨" && level_cn="严重"
  action_line="无"; ((${#RELOGIN_CMDS[@]} > 0)) && action_line="请仅重登失效账号（见报告 reloginCommands）"
  msg="${icon} OpenClaw 健康检查（${PROVIDER}）\n状态：${level_cn} (${level})\n阶段：${state}\n账号数：${#ALL_PROFILES[@]}\n失效账号：${failed_csv}\n异常原因：${reason}\n处理建议：${action_line}\n报告：${LATEST_JSON}"

  prev_level="PASS"; prev_alert_ts=0; prev_signature=""
  if [[ -f "$ALERT_STATE_FILE" ]]; then
    prev_level="$(node -e "const fs=require('fs');try{const o=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(String(o.level||'PASS'));}catch{process.stdout.write('PASS')}" "$ALERT_STATE_FILE")"
    prev_alert_ts="$(node -e "const fs=require('fs');try{const o=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(String(Number(o.lastAlertTs||0)));}catch{process.stdout.write('0')}" "$ALERT_STATE_FILE")"
    prev_signature="$(node -e "const fs=require('fs');try{const o=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(String(o.signature||''));}catch{process.stdout.write('')}" "$ALERT_STATE_FILE")"
  fi
  signature="$level|$ANOMALY_CLASS|$failed_csv"
  send_once(){ openclaw message send --channel "$TELEGRAM_CHANNEL" --target "$TELEGRAM_TARGET" --message "$1" >/dev/null 2>&1 || true; }

  if [[ "$level" != "PASS" ]]; then
    if [[ "$prev_level" == "PASS" || "$prev_signature" != "$signature" ]]; then
      i=1; while (( i <= ALERT_BURST_COUNT )); do send_once "$msg\n第 ${i}/${ALERT_BURST_COUNT} 次告警"; i=$((i+1)); done
      echo "{\"level\":\"$level\",\"lastAlertTs\":$NOW_TS,\"signature\":\"$signature\"}" > "$ALERT_STATE_FILE"
    else
      delta=$((NOW_TS-prev_alert_ts))
      if (( delta >= ALERT_REMIND_SECONDS )); then
        send_once "$msg\n持续异常提醒"
        echo "{\"level\":\"$level\",\"lastAlertTs\":$NOW_TS,\"signature\":\"$signature\"}" > "$ALERT_STATE_FILE"
      elif (( delta < ALERT_DEDUP_SECONDS )); then
        : # dedup window
      fi
    fi
  else
    [[ "$prev_level" != "PASS" ]] && send_once "✅ OpenClaw 健康恢复（${PROVIDER}）\n阶段：Recovered\n报告：${LATEST_JSON}"
    echo "{\"level\":\"PASS\",\"lastAlertTs\":$NOW_TS,\"signature\":\"PASS\"}" > "$ALERT_STATE_FILE"
  fi
else
  log "dry-run enabled: skip Telegram notify"
fi

exit "$exit_code"
