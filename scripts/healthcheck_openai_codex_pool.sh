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
ALERT_BURST_COUNT="${OCX_ALERT_BURST_COUNT:-1}"
ALERT_REMIND_SECONDS="${OCX_ALERT_REMIND_SECONDS:-21600}"
ALERT_DEDUP_SECONDS="${OCX_ALERT_DEDUP_SECONDS:-3600}"
ALERT_SUPPRESS_COOLDOWN_ONLY="${OCX_ALERT_SUPPRESS_COOLDOWN_ONLY:-1}"
AUTO_REPAIR="${OCX_AUTO_REPAIR:-0}"
REPAIR_MIN_INTERVAL="${OCX_REPAIR_MIN_INTERVAL_SECONDS:-1800}"
AUTO_REORDER="${OCX_AUTO_REORDER:-0}"
AUTO_REORDER_ACCOUNT_DIVERSITY="${OCX_AUTO_REORDER_ACCOUNT_DIVERSITY:-1}"
CB_FAIL_THRESHOLD="${OCX_CB_FAIL_THRESHOLD:-3}"
CB_COOLDOWN_SECONDS="${OCX_CB_COOLDOWN_SECONDS:-3600}"
# Smarter circuit-breaker tuning by failure type
CB_FAIL_THRESHOLD_AUTH="${OCX_CB_FAIL_THRESHOLD_AUTH:-3}"
CB_FAIL_THRESHOLD_NETWORK="${OCX_CB_FAIL_THRESHOLD_NETWORK:-5}"
CB_FAIL_THRESHOLD_OTHER="${OCX_CB_FAIL_THRESHOLD_OTHER:-5}"
CB_COOLDOWN_SECONDS_AUTH="${OCX_CB_COOLDOWN_SECONDS_AUTH:-3600}"
CB_COOLDOWN_SECONDS_NETWORK="${OCX_CB_COOLDOWN_SECONDS_NETWORK:-900}"
CB_COOLDOWN_SECONDS_OTHER="${OCX_CB_COOLDOWN_SECONDS_OTHER:-900}"
# Half-open probe: allow early re-check near cooldown end
CB_HALF_OPEN_WINDOW_SECONDS="${OCX_CB_HALF_OPEN_WINDOW_SECONDS:-300}"
# Optional per-profile override for default profile
CB_FAIL_THRESHOLD_DEFAULT="${OCX_CB_FAIL_THRESHOLD_DEFAULT:-0}"
CB_COOLDOWN_SECONDS_DEFAULT="${OCX_CB_COOLDOWN_SECONDS_DEFAULT:-0}"
# Cooldown jitter + failcount decay
CB_COOLDOWN_JITTER_MIN_SECONDS="${OCX_CB_COOLDOWN_JITTER_MIN_SECONDS:-30}"
CB_COOLDOWN_JITTER_MAX_SECONDS="${OCX_CB_COOLDOWN_JITTER_MAX_SECONDS:-120}"
CB_FAILCOUNT_DECAY_ENABLED="${OCX_CB_FAILCOUNT_DECAY_ENABLED:-1}"
CB_FAILCOUNT_DECAY_INTERVAL_SECONDS="${OCX_CB_FAILCOUNT_DECAY_INTERVAL_SECONDS:-1800}"
DRY_RUN="${OCX_DRY_RUN:-0}"
CODEX_AUTH_PATH="${OCX_CODEX_AUTH_PATH:-/root/.codex/auth.json}"
AUTH_PROFILES_PATH="${OCX_AUTH_PROFILES_PATH:-/root/.openclaw/agents/main/agent/auth-profiles.json}"
PROBE_HINT_FORCE_TRIP="${OCX_PROBE_HINT_FORCE_TRIP:-1}"
PROBE_HINT_MIN_COOLDOWN_SECONDS="${OCX_PROBE_HINT_MIN_COOLDOWN_SECONDS:-1800}"
PROBE_HINT_MAX_COOLDOWN_SECONDS="${OCX_PROBE_HINT_MAX_COOLDOWN_SECONDS:-259200}"
PROBE_HINT_DEMOTE_WITHOUT_AUTO_REORDER="${OCX_PROBE_HINT_DEMOTE_WITHOUT_AUTO_REORDER:-1}"
HARD_DISABLE_FAILED="${OCX_HARD_DISABLE_FAILED:-1}"
HARD_DISABLE_FAILED_ACCOUNT="${OCX_HARD_DISABLE_FAILED_ACCOUNT:-1}"
ACCOUNT_QUARANTINE_SECONDS="${OCX_ACCOUNT_QUARANTINE_SECONDS:-7200}"
RECOVERY_SUCCESS_ROUNDS="${OCX_RECOVERY_SUCCESS_ROUNDS:-2}"
HARD_DISABLE_MIN_ACTIVE_PROFILES="${OCX_HARD_DISABLE_MIN_ACTIVE_PROFILES:-2}"
HARD_DISABLE_MIN_ACTIVE_ACCOUNTS="${OCX_HARD_DISABLE_MIN_ACTIVE_ACCOUNTS:-1}"

mkdir -p "$REPORT_DIR" "$RUN_DIR" "$CONFIG_HISTORY_DIR"
DATE_UTC="$(date -u +%Y%m%d)"
TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_TS="$(date +%s)"
LOG_FILE="$REPORT_DIR/openai_codex_health_${DATE_UTC}.log"
LATEST_JSON="$REPORT_DIR/openai_codex_health_latest.json"

WARNINGS=(); CRITICALS=(); RELOGIN_CMDS=(); FAILED_PROFILES=(); EXPIRING_PROFILES=(); ALL_PROFILES=(); UNUSABLE_PROFILES=(); COOLDOWN_PROFILES=(); ACTIVE_PROFILES=(); QUARANTINED_PROFILES=(); QUARANTINED_ACCOUNTS=(); ORDER_INPUT_PROFILES=();
declare -A PROFILE_EMAIL_MAP PROFILE_REMAINING PROFILE_SCORE PROFILE_FAILCOUNT PROFILE_COOLDOWN_UNTIL PROFILE_ACCOUNT_MAP PROFILE_HINT_COOLDOWN PROFILE_FORCE_TRIP PROFILE_RECOVERY_STREAK PROFILE_QUARANTINED

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
  while IFS=$'\t' read -r k fail cooldown recovery quarantined; do
    [[ -n "$k" ]] || continue
    PROFILE_FAILCOUNT["$k"]="${fail:-0}"
    PROFILE_COOLDOWN_UNTIL["$k"]="${cooldown:-0}"
    PROFILE_RECOVERY_STREAK["$k"]="${recovery:-0}"
    PROFILE_QUARANTINED["$k"]="${quarantined:-0}"
  done < <(STATE="$POOL_STATE_FILE" node - <<'NODE'
const fs=require('fs');
try{
  const s=JSON.parse(fs.readFileSync(process.env.STATE,'utf8'));
  const p=s.profiles||{};
  for(const k of Object.keys(p)){
    const row=p[k]||{};
    console.log(`${k}\t${Number(row.failCount||0)}\t${Number(row.cooldownUntil||0)}\t${Number(row.recoveryStreak||0)}\t${Number(row.quarantined||0)}`);
  }
}catch{}
NODE
)
fi

# failcount decay: reduce historical penalties over time
if [[ "$CB_FAILCOUNT_DECAY_ENABLED" == "1" && "$CB_FAILCOUNT_DECAY_INTERVAL_SECONDS" =~ ^[0-9]+$ && $CB_FAILCOUNT_DECAY_INTERVAL_SECONDS -gt 0 ]]; then
  for k in "${!PROFILE_FAILCOUNT[@]}"; do
    fc="${PROFILE_FAILCOUNT[$k]:-0}"
    cu="${PROFILE_COOLDOWN_UNTIL[$k]:-0}"
    [[ "$fc" =~ ^[0-9]+$ ]] || continue
    [[ "$cu" =~ ^[0-9]+$ ]] || cu=0
    if (( fc > 0 && cu > 0 && NOW_TS > cu )); then
      elapsed=$((NOW_TS - cu))
      decay_steps=$((elapsed / CB_FAILCOUNT_DECAY_INTERVAL_SECONDS))
      if (( decay_steps > 0 )); then
        new_fc=$((fc - decay_steps)); (( new_fc < 0 )) && new_fc=0
        PROFILE_FAILCOUNT["$k"]="$new_fc"
      fi
    fi
  done
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
  IFS=$'\t' read -r pid rem account_id <<< "$line"
  ALL_PROFILES+=("$pid"); PROFILE_REMAINING["$pid"]="$rem"
  [[ -n "${account_id:-}" ]] && PROFILE_ACCOUNT_MAP["$pid"]="$account_id"
  cooldown_until="${PROFILE_COOLDOWN_UNTIL[$pid]:-0}"
  if (( cooldown_until > NOW_TS )); then
    remain_cd=$((cooldown_until - NOW_TS))
    # half-open: near cooldown end we probe once instead of hard skipping
    if (( remain_cd > CB_HALF_OPEN_WINDOW_SECONDS )); then
      COOLDOWN_PROFILES+=("$pid")
      WARNINGS+=("cooldown active: ${pid#${PROFILE_PREFIX}} until $(date -u -d @${cooldown_until} +%H:%M:%S 2>/dev/null || echo ${cooldown_until})")
      continue
    else
      WARNINGS+=("half-open probe: ${pid#${PROFILE_PREFIX}} cooldown remaining ${remain_cd}s")
    fi
  fi
  if [[ "$rem" =~ ^-?[0-9]+$ ]]; then
    if (( rem < 0 )); then FAILED_PROFILES+=("$pid")
    elif (( rem < EXPIRING_MS )); then EXPIRING_PROFILES+=("$pid:$rem")
    fi
  fi
done < <(PARSED="$parsed_json" node - <<'NODE'
const d=JSON.parse(process.env.PARSED||'{}');
for(const p of (d.oauthProfiles||[])){
  const aid=(p && p.accountId!=null) ? String(p.accountId).replace(/\t/g,' ').trim() : '';
  console.log(`${p.profileId}\t${Number(p.remainingMs||0)}\t${aid}`);
}
NODE
)

# fallback: models status may not expose accountId; read from auth-profiles store when available
if [[ -f "$AUTH_PROFILES_PATH" && ${#ALL_PROFILES[@]} -gt 0 ]]; then
  while IFS=$'\t' read -r pid aid; do
    [[ -n "$pid" && -n "$aid" ]] || continue
    [[ -z "${PROFILE_ACCOUNT_MAP[$pid]:-}" ]] && PROFILE_ACCOUNT_MAP["$pid"]="$aid"
  done < <(AUTH_PROFILES_PATH="$AUTH_PROFILES_PATH" PROFILES_JOINED="$(printf '%s\n' "${ALL_PROFILES[@]:-}")" node - <<'NODE'
const fs=require('fs');
const profiles=String(process.env.PROFILES_JOINED||'').split('\n').map(x=>x.trim()).filter(Boolean);
let store={};
try{store=JSON.parse(fs.readFileSync(process.env.AUTH_PROFILES_PATH,'utf8'));}catch{}
const map=(store&&store.profiles&&typeof store.profiles==='object')?store.profiles:{};
for(const pid of profiles){
  const aid=map?.[pid]?.accountId;
  if(aid!=null && String(aid).trim()) console.log(`${pid}\t${String(aid).replace(/\t/g,' ').trim()}`);
}
NODE
)
fi

for u in "${UNUSABLE_PROFILES[@]:-}"; do [[ -n "$u" ]] && FAILED_PROFILES+=("$u"); done
if ((${#FAILED_PROFILES[@]} > 0)); then mapfile -t FAILED_PROFILES < <(printf '%s\n' "${FAILED_PROFILES[@]}" | awk 'NF' | sort -u); fi
if ((${#FAILED_PROFILES[@]} > 0)); then WARNINGS+=("failed profiles detected: ${#FAILED_PROFILES[@]}"); fi
if ((${#EXPIRING_PROFILES[@]} > 0)); then WARNINGS+=("expiring profiles detected: ${#EXPIRING_PROFILES[@]}"); fi

# coarse error hints from current status/probe payload (used to improve breaker typing)
STATUS_HAS_AUTH=0
STATUS_HAS_NETWORK=0
if echo "$status_json" | grep -Eqi 'expired|invalid|oauth|unauth|forbidden|banned|account'; then STATUS_HAS_AUTH=1; fi
if echo "$status_json" | grep -Eqi 'timeout|connect|dns|network|tls|econn|enotfound|proxy'; then STATUS_HAS_NETWORK=1; fi


# multi-probe (run before scoring so probe hints can participate in breaker decisions)
probe1_out="$(timeout "$OPENCLAW_AGENT_TIMEOUT" openclaw agent --session-id "healthcheck-$(date -u +%Y%m%dT%H%M%SZ)-a" --message "Reply exactly: ok" --thinking off --json 2>&1 || true)"
probe2_out="$(timeout "$OPENCLAW_AGENT_TIMEOUT" openclaw agent --session-id "healthcheck-$(date -u +%Y%m%dT%H%M%SZ)-b" --message "Reply exactly: pong" --thinking off --json 2>&1 || true)"
probe1_ok=0; probe2_ok=0
probe_hint_quota=0; probe_hint_auth=0; probe_hint_provider=0
probe_retry_after_minutes=0
probe_combined_lc=""
inferred_fail_profile=""
echo "$probe1_out" | grep -Eq '"text"\s*:\s*"ok"' && probe1_ok=1
echo "$probe2_out" | grep -Eq '"text"\s*:\s*"pong"' && probe2_ok=1
if (( probe1_ok==0 && probe2_ok==0 )); then
  CRITICALS+=("both probes failed")
elif (( probe1_ok==0 || probe2_ok==0 )); then
  WARNINGS+=("one probe failed")
fi
if (( probe1_ok==0 || probe2_ok==0 )); then
  probe_combined_lc="$(printf '%s\n%s\n' "$probe1_out" "$probe2_out" | tr '[:upper:]' '[:lower:]')"
  if echo "$probe_combined_lc" | grep -Eqi 'you have hit your chatgpt usage limit|usage[[:space:]]+limit|api[[:space:]]+rate[[:space:]]+limit([[:space:]]+reached)?|rate[[:space:]-]*limit'; then
    probe_hint_quota=1
    WARNINGS+=("probe hint: quota/rate-limit pressure (not pure network outage)")
  fi
  if echo "$probe_combined_lc" | grep -Eqi 'authentication[[:space:]]+token([[:space:]]+has)?[[:space:]]+been[[:space:]]+invalidated|authentication[[:space:]]+token[[:space:]]+invalidated|token([[:space:]]+has)?[[:space:]]+been[[:space:]]+invalidated|please[[:space:]]+try[[:space:]]+signing[[:space:]]+in[[:space:]]+again'; then
    probe_hint_auth=1
    WARNINGS+=("probe hint: auth token invalidated / re-login required (not pure network outage)")
  fi
  if echo "$probe_combined_lc" | grep -Eqi 'connected[[:space:]]*\|[[:space:]]*error|run[[:space:]]+error'; then
    probe_hint_provider=1
    WARNINGS+=("probe hint: provider runtime returned connected|error")
  fi
  retry_after_raw="$(echo "$probe_combined_lc" | grep -Eo 'try[[:space:]]+again[[:space:]]+in[[:space:]]*~?[0-9]+[[:space:]]*min' | head -n1 || true)"
  if [[ -n "$retry_after_raw" ]]; then
    probe_retry_after_minutes="$(echo "$retry_after_raw" | sed -E 's/.*~?([0-9]+).*/\1/' || true)"
    if [[ "$probe_retry_after_minutes" =~ ^[0-9]+$ && $probe_retry_after_minutes -gt 0 ]]; then
      WARNINGS+=("probe hint: upstream retry-after about ${probe_retry_after_minutes} min")
    else
      probe_retry_after_minutes=0
    fi
  fi
fi

# Probe-driven inferred failure: if runtime clearly indicates auth/quota pressure, quarantine the likely active profile immediately.
if (( (probe_hint_quota==1 || probe_hint_auth==1 || probe_hint_provider==1) && ${#ALL_PROFILES[@]} > 0 )); then
  inferred_fail_profile="$(AUTH_PROFILES_PATH="$AUTH_PROFILES_PATH" PROVIDER="$PROVIDER" ALL_PROFILES_JOINED="$(printf '%s\n' "${ALL_PROFILES[@]:-}")" node - <<'NODE'
const fs=require('fs');
const split=(s)=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const all=split(process.env.ALL_PROFILES_JOINED);
const provider=String(process.env.PROVIDER||'openai-codex');
let store={};
try{store=JSON.parse(fs.readFileSync(process.env.AUTH_PROFILES_PATH,'utf8'));}catch{}
const order=(store&&store.order&&Array.isArray(store.order[provider]))?store.order[provider]:[];
const lastGood=(store&&store.lastGood)?String(store.lastGood[provider]||'').trim():'';
const inAll=(id)=>all.includes(id);
let pick='';
for(const id of order){ if(inAll(id)){ pick=id; break; } }
if(!pick && lastGood && inAll(lastGood)) pick=lastGood;
if(!pick && all.length>0) pick=all[0];
if(pick) process.stdout.write(pick);
NODE
)"
  if [[ -z "$inferred_fail_profile" ]]; then inferred_fail_profile="${ALL_PROFILES[0]:-}"; fi

  if [[ -n "$inferred_fail_profile" ]]; then
    already_failed=0
    for fp in "${FAILED_PROFILES[@]:-}"; do [[ "$fp" == "$inferred_fail_profile" ]] && already_failed=1 && break; done
    if (( already_failed==0 )); then FAILED_PROFILES+=("$inferred_fail_profile"); fi
    WARNINGS+=("probe inferred failing profile: ${inferred_fail_profile#${PROFILE_PREFIX}}")

    if [[ "$PROBE_HINT_FORCE_TRIP" == "1" ]]; then PROFILE_FORCE_TRIP["$inferred_fail_profile"]=1; fi

    if [[ "$probe_retry_after_minutes" =~ ^[0-9]+$ && $probe_retry_after_minutes -gt 0 ]]; then
      inferred_cd=$((probe_retry_after_minutes*60))
      if [[ "$PROBE_HINT_MIN_COOLDOWN_SECONDS" =~ ^[0-9]+$ && $inferred_cd -lt $PROBE_HINT_MIN_COOLDOWN_SECONDS ]]; then inferred_cd=$PROBE_HINT_MIN_COOLDOWN_SECONDS; fi
      if [[ "$PROBE_HINT_MAX_COOLDOWN_SECONDS" =~ ^[0-9]+$ && $PROBE_HINT_MAX_COOLDOWN_SECONDS -gt 0 && $inferred_cd -gt $PROBE_HINT_MAX_COOLDOWN_SECONDS ]]; then inferred_cd=$PROBE_HINT_MAX_COOLDOWN_SECONDS; fi
      PROFILE_HINT_COOLDOWN["$inferred_fail_profile"]="$inferred_cd"
    fi
  fi
fi

if (( probe_hint_quota==1 || probe_hint_auth==1 )); then STATUS_HAS_AUTH=1; fi

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

  # smarter failure typing: per-profile expiry first, then probe/status hints (auth/network), then fallback other
  rem="${PROFILE_REMAINING[$f]:-0}"
  fail_type="other"
  threshold="$CB_FAIL_THRESHOLD_OTHER"
  cooldown_secs="$CB_COOLDOWN_SECONDS_OTHER"
  if [[ "$rem" =~ ^-?[0-9]+$ ]] && (( rem < 0 )); then
    fail_type="auth"
    threshold="$CB_FAIL_THRESHOLD_AUTH"
    cooldown_secs="$CB_COOLDOWN_SECONDS_AUTH"
  elif (( probe_hint_auth==1 || probe_hint_quota==1 )); then
    fail_type="auth"
    threshold="$CB_FAIL_THRESHOLD_AUTH"
    cooldown_secs="$CB_COOLDOWN_SECONDS_AUTH"
  elif (( STATUS_HAS_NETWORK == 1 && STATUS_HAS_AUTH == 0 )); then
    fail_type="network"
    threshold="$CB_FAIL_THRESHOLD_NETWORK"
    cooldown_secs="$CB_COOLDOWN_SECONDS_NETWORK"
  elif (( STATUS_HAS_AUTH == 1 )); then
    fail_type="auth"
    threshold="$CB_FAIL_THRESHOLD_AUTH"
    cooldown_secs="$CB_COOLDOWN_SECONDS_AUTH"
  fi

  # optional stricter/looser override for default profile
  if [[ "$f" == "${PROFILE_PREFIX}default" ]]; then
    (( CB_FAIL_THRESHOLD_DEFAULT > 0 )) && threshold="$CB_FAIL_THRESHOLD_DEFAULT"
    (( CB_COOLDOWN_SECONDS_DEFAULT > 0 )) && cooldown_secs="$CB_COOLDOWN_SECONDS_DEFAULT"
  fi

  if [[ "${PROFILE_FORCE_TRIP[$f]:-0}" == "1" ]]; then threshold=1; fi
  hint_cd="${PROFILE_HINT_COOLDOWN[$f]:-0}"
  if [[ "$hint_cd" =~ ^[0-9]+$ ]] && (( hint_cd > cooldown_secs )); then cooldown_secs="$hint_cd"; fi

  if (( cur >= threshold )); then
    jitter=0
    if [[ "$CB_COOLDOWN_JITTER_MIN_SECONDS" =~ ^[0-9]+$ && "$CB_COOLDOWN_JITTER_MAX_SECONDS" =~ ^[0-9]+$ && $CB_COOLDOWN_JITTER_MAX_SECONDS -ge $CB_COOLDOWN_JITTER_MIN_SECONDS ]]; then
      if (( CB_COOLDOWN_JITTER_MAX_SECONDS > CB_COOLDOWN_JITTER_MIN_SECONDS )); then
        span=$((CB_COOLDOWN_JITTER_MAX_SECONDS - CB_COOLDOWN_JITTER_MIN_SECONDS + 1))
        jitter=$((CB_COOLDOWN_JITTER_MIN_SECONDS + RANDOM % span))
      else
        jitter=$CB_COOLDOWN_JITTER_MIN_SECONDS
      fi
    fi
    final_cooldown=$((cooldown_secs + jitter))
    PROFILE_COOLDOWN_UNTIL["$f"]=$((NOW_TS + final_cooldown))
    WARNINGS+=("circuit breaker tripped: ${f#${PROFILE_PREFIX}} (${fail_type}) for ${final_cooldown}s")
  fi
  short="${f#${PROFILE_PREFIX}}"
  RELOGIN_CMDS+=("$short: codex logout && codex -c cli_auth_credentials_store='file' login --device-auth && $BASE_DIR/scripts/import_codex_auth_to_openclaw.sh $f main $CODEX_AUTH_PATH")
done

# quarantine failed-account siblings (account-level isolation)
if [[ "$HARD_DISABLE_FAILED" == "1" && "$HARD_DISABLE_FAILED_ACCOUNT" == "1" && "$ACCOUNT_QUARANTINE_SECONDS" =~ ^[0-9]+$ && $ACCOUNT_QUARANTINE_SECONDS -gt 0 ]]; then
  declare -A _qacc_seen
  for f in "${FAILED_PROFILES[@]:-}"; do
    [[ -n "$f" ]] || continue
    aid="${PROFILE_ACCOUNT_MAP[$f]:-}"
    [[ -n "$aid" ]] || continue
    [[ -n "${_qacc_seen[$aid]:-}" ]] && continue
    _qacc_seen["$aid"]=1
    QUARANTINED_ACCOUNTS+=("$aid")
    target_cd=$((NOW_TS + ACCOUNT_QUARANTINE_SECONDS))
    for p in "${ALL_PROFILES[@]:-}"; do
      [[ "${PROFILE_ACCOUNT_MAP[$p]:-}" == "$aid" ]] || continue
      cur_cd="${PROFILE_COOLDOWN_UNTIL[$p]:-0}"
      [[ "$cur_cd" =~ ^[0-9]+$ ]] || cur_cd=0
      if (( target_cd > cur_cd )); then PROFILE_COOLDOWN_UNTIL["$p"]="$target_cd"; fi
      PROFILE_QUARANTINED["$p"]=1
      PROFILE_RECOVERY_STREAK["$p"]=0
    done
  done
fi

# recovery gate: quarantined profiles need N consecutive healthy rounds after cooldown expiry
for p in "${ALL_PROFILES[@]:-}"; do
  bad=0
  for f in "${FAILED_PROFILES[@]:-}"; do [[ "$p" == "$f" ]] && bad=1 && break; done

  rem="${PROFILE_REMAINING[$p]:-0}"
  rem_bad=0
  if [[ "$rem" =~ ^-?[0-9]+$ ]] && (( rem < 0 )); then rem_bad=1; fi

  unusable=0
  for u in "${UNUSABLE_PROFILES[@]:-}"; do [[ "$p" == "$u" ]] && unusable=1 && break; done

  healthy_signal=1
  (( bad==1 || rem_bad==1 || unusable==1 )) && healthy_signal=0

  cooldown_until="${PROFILE_COOLDOWN_UNTIL[$p]:-0}"
  [[ "$cooldown_until" =~ ^[0-9]+$ ]] || cooldown_until=0

  # any direct failure immediately enters quarantine
  if (( healthy_signal == 0 )); then
    PROFILE_QUARANTINED["$p"]=1
    PROFILE_RECOVERY_STREAK["$p"]=0
    continue
  fi

  # cooldown still active -> keep quarantined
  if (( cooldown_until > NOW_TS )); then
    PROFILE_QUARANTINED["$p"]=1
    PROFILE_RECOVERY_STREAK["$p"]=0
    continue
  fi

  if [[ "${PROFILE_QUARANTINED[$p]:-0}" == "1" ]]; then
    streak="${PROFILE_RECOVERY_STREAK[$p]:-0}"
    [[ "$streak" =~ ^[0-9]+$ ]] || streak=0
    streak=$((streak+1))
    PROFILE_RECOVERY_STREAK["$p"]="$streak"
    if (( streak >= RECOVERY_SUCCESS_ROUNDS )); then
      PROFILE_QUARANTINED["$p"]=0
      PROFILE_RECOVERY_STREAK["$p"]=0
      PROFILE_FAILCOUNT["$p"]=0
      PROFILE_COOLDOWN_UNTIL["$p"]=0
    fi
  else
    PROFILE_RECOVERY_STREAK["$p"]=0
    PROFILE_FAILCOUNT["$p"]=0
  fi
done

# build active vs quarantined pool and enforce hard isolation for order input
active_account_count=0
ACTIVE_PROFILES=("${ALL_PROFILES[@]:-}")
QUARANTINED_PROFILES=()
ORDER_INPUT_PROFILES=("${ALL_PROFILES[@]:-}")
if [[ "$HARD_DISABLE_FAILED" == "1" ]]; then
  ACTIVE_PROFILES=(); QUARANTINED_PROFILES=()
  for p in "${ALL_PROFILES[@]:-}"; do
    q="${PROFILE_QUARANTINED[$p]:-0}"
    cd="${PROFILE_COOLDOWN_UNTIL[$p]:-0}"
    [[ "$cd" =~ ^[0-9]+$ ]] || cd=0
    if (( cd > NOW_TS )); then q=1; fi
    if [[ "$q" == "1" ]]; then
      QUARANTINED_PROFILES+=("$p")
    else
      ACTIVE_PROFILES+=("$p")
    fi
  done

  active_account_count="$(ACTIVE_JOINED="$(printf '%s\n' "${ACTIVE_PROFILES[@]:-}")" ACCOUNT_JOINED="$(for p in "${ALL_PROFILES[@]:-}"; do [[ -n "${PROFILE_ACCOUNT_MAP[$p]:-}" ]] && echo "$p=${PROFILE_ACCOUNT_MAP[$p]}"; done)" node - <<'NODE'
const split=(s)=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const mapFrom=(s)=>{const o={}; for(const l of split(s)){ const i=l.indexOf('='); if(i>0) o[l.slice(0,i).trim()]=l.slice(i+1).trim(); } return o; };
const active=split(process.env.ACTIVE_JOINED);
const accMap=mapFrom(process.env.ACCOUNT_JOINED);
const set=new Set();
for(const p of active){
  const aid=String(accMap[p]||'').trim();
  set.add(aid ? `acc:${aid}` : `profile:${p}`);
}
process.stdout.write(String(set.size));
NODE
)"
  [[ "$active_account_count" =~ ^[0-9]+$ ]] || active_account_count=0

  if (( ${#ACTIVE_PROFILES[@]} >= HARD_DISABLE_MIN_ACTIVE_PROFILES && active_account_count >= HARD_DISABLE_MIN_ACTIVE_ACCOUNTS )); then
    ORDER_INPUT_PROFILES=("${ACTIVE_PROFILES[@]:-}")
  else
    ORDER_INPUT_PROFILES=("${ALL_PROFILES[@]:-}")
    WARNINGS+=("hard isolate fail-open: active=${#ACTIVE_PROFILES[@]} (need >=${HARD_DISABLE_MIN_ACTIVE_PROFILES}), accounts=${active_account_count} (need >=${HARD_DISABLE_MIN_ACTIVE_ACCOUNTS})")
  fi
fi

if (( active_account_count == 0 && ${#ACTIVE_PROFILES[@]} > 0 )); then
  active_account_count="$(ACTIVE_JOINED="$(printf '%s\n' "${ACTIVE_PROFILES[@]:-}")" ACCOUNT_JOINED="$(for p in "${ALL_PROFILES[@]:-}"; do [[ -n "${PROFILE_ACCOUNT_MAP[$p]:-}" ]] && echo "$p=${PROFILE_ACCOUNT_MAP[$p]}"; done)" node - <<'NODE'
const split=(s)=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const mapFrom=(s)=>{const o={}; for(const l of split(s)){ const i=l.indexOf('='); if(i>0) o[l.slice(0,i).trim()]=l.slice(i+1).trim(); } return o; };
const active=split(process.env.ACTIVE_JOINED);
const accMap=mapFrom(process.env.ACCOUNT_JOINED);
const set=new Set();
for(const p of active){
  const aid=String(accMap[p]||'').trim();
  set.add(aid ? `acc:${aid}` : `profile:${p}`);
}
process.stdout.write(String(set.size));
NODE
)"
  [[ "$active_account_count" =~ ^[0-9]+$ ]] || active_account_count=0
fi

# recommendations
if (( ${#ALL_PROFILES[@]} < RECOMMENDED_MIN )); then WARNINGS+=("profile count below recommendation: ${#ALL_PROFILES[@]} < ${RECOMMENDED_MIN}"); fi
if (( ${#ALL_PROFILES[@]} > RECOMMENDED_MAX )); then WARNINGS+=("profile count above recommendation: ${#ALL_PROFILES[@]} > ${RECOMMENDED_MAX}"); fi

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
if ((${#CRITICALS[@]} > 0 || ${#WARNINGS[@]} > 0 || ${#FAILED_PROFILES[@]} > 0 || ${#EXPIRING_PROFILES[@]} > 0)); then state="Degraded"; fi
if [[ "$AUTO_REPAIR" == "1" && "$state" == "Degraded" && "$DRY_RUN" != "1" ]]; then state="Repairing"; fi

# immediate probe-driven failover when auto reorder is disabled
if [[ "$AUTO_REORDER" != "1" && "$PROBE_HINT_DEMOTE_WITHOUT_AUTO_REORDER" == "1" && -n "${inferred_fail_profile:-}" && ${#ALL_PROFILES[@]} -gt 0 ]]; then
  mapfile -t probe_demote_order < <(
    AUTH_PROFILES_PATH="$AUTH_PROFILES_PATH" PROVIDER="$PROVIDER" FAILED_PROFILE="$inferred_fail_profile" ALL_PROFILES_JOINED="$(printf '%s\n' "${ALL_PROFILES[@]:-}")" node - <<'NODE'
const fs=require('fs');
const split=(s)=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const all=split(process.env.ALL_PROFILES_JOINED);
const provider=String(process.env.PROVIDER||'openai-codex');
const failed=String(process.env.FAILED_PROFILE||'').trim();
let store={};
try{store=JSON.parse(fs.readFileSync(process.env.AUTH_PROFILES_PATH,'utf8'));}catch{}
let order=(store&&store.order&&Array.isArray(store.order[provider]))?store.order[provider]:[];
if(!Array.isArray(order) || order.length===0) order=[...all];
const seen=new Set();
const normalized=[];
for(const id of order){ if(all.includes(id) && !seen.has(id)){ normalized.push(id); seen.add(id); } }
for(const id of all){ if(!seen.has(id)){ normalized.push(id); seen.add(id); } }
if(!failed || !normalized.includes(failed)){
  for(const id of normalized) console.log(id);
  process.exit(0);
}
const out=[...normalized.filter(x=>x!==failed), failed];
for(const id of out) console.log(id);
NODE
  )
  if ((${#probe_demote_order[@]} > 0)); then
    if openclaw models auth order set --agent main --provider "$PROVIDER" "${probe_demote_order[@]}" >/dev/null 2>&1; then
      WARNINGS+=("probe failover applied: demoted ${inferred_fail_profile#${PROFILE_PREFIX}} to order tail")
    else
      WARNINGS+=("probe failover apply failed for ${inferred_fail_profile#${PROFILE_PREFIX}}")
    fi
  fi
fi

# auto reorder by health score
if [[ "$AUTO_REORDER" == "1" && ${#ORDER_INPUT_PROFILES[@]} -gt 0 ]]; then
  mapfile -t sorted_profiles < <(
    AUTO_REORDER_ACCOUNT_DIVERSITY="$AUTO_REORDER_ACCOUNT_DIVERSITY" \
    ALL_PROFILES_JOINED="$(printf '%s\n' "${ORDER_INPUT_PROFILES[@]:-}")" \
    SCORE_JOINED="$(for p in "${ORDER_INPUT_PROFILES[@]:-}"; do echo "$p=${PROFILE_SCORE[$p]:-0}"; done)" \
    ACCOUNT_JOINED="$(for p in "${ORDER_INPUT_PROFILES[@]:-}"; do [[ -n "${PROFILE_ACCOUNT_MAP[$p]:-}" ]] && echo "$p=${PROFILE_ACCOUNT_MAP[$p]}"; done)" \
    node - <<'NODE'
const split=(s)=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const mapFrom=(s)=>{const o={}; for(const l of split(s)){const i=l.indexOf('='); if(i>0) o[l.slice(0,i).trim()]=l.slice(i+1).trim();} return o;};
const profiles=split(process.env.ALL_PROFILES_JOINED);
const scoreMap=mapFrom(process.env.SCORE_JOINED);
const accountMap=mapFrom(process.env.ACCOUNT_JOINED);
const useDiversity=String(process.env.AUTO_REORDER_ACCOUNT_DIVERSITY||'1')!=='0';
const items=profiles.map((id)=>({
  id,
  score:Number(scoreMap[id]||0),
  accountId:String(accountMap[id]||'').trim()
})).sort((a,b)=> (b.score-a.score) || a.id.localeCompare(b.id));

if(!useDiversity){
  for(const it of items) console.log(it.id);
  process.exit(0);
}

const groups=new Map();
for(const it of items){
  const key=it.accountId ? `acc:${it.accountId}` : `single:${it.id}`;
  if(!groups.has(key)) groups.set(key, []);
  groups.get(key).push(it);
}
const lanes=[...groups.entries()]
  .map(([key,queue])=>({key,queue}))
  .sort((a,b)=> (b.queue[0].score-a.queue[0].score) || a.key.localeCompare(b.key));

for(;;){
  let emitted=0;
  for(const lane of lanes){
    if(lane.queue.length===0) continue;
    console.log(lane.queue.shift().id);
    emitted+=1;
  }
  if(emitted===0) break;
}
NODE
  )
  if ((${#sorted_profiles[@]} > 0)); then
    openclaw models auth order set --agent main --provider "$PROVIDER" "${sorted_profiles[@]}" >/dev/null 2>&1 || WARNINGS+=("auto reorder failed")
  fi
fi

# enforce hard-isolation order when auto reorder is disabled
if [[ "$AUTO_REORDER" != "1" && "$HARD_DISABLE_FAILED" == "1" && ${#ORDER_INPUT_PROFILES[@]} -gt 0 ]]; then
  if openclaw models auth order set --agent main --provider "$PROVIDER" "${ORDER_INPUT_PROFILES[@]}" >/dev/null 2>&1; then
    WARNINGS+=("hard isolate order applied (auto reorder disabled)")
  else
    WARNINGS+=("hard isolate order apply failed")
  fi
fi

# sync auth order always best effort
sync_note=""
if [[ "$AUTO_REORDER" == "1" ]]; then
  sync_note="sync skipped (auto reorder enabled)"
elif [[ -x "$BASE_DIR/scripts/sync_openclaw_auth_order.sh" ]]; then
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
PROFILES_JOINED="$(for p in "${ALL_PROFILES[@]:-}"; do echo "$p|${PROFILE_FAILCOUNT[$p]:-0}|${PROFILE_COOLDOWN_UNTIL[$p]:-0}|${PROFILE_RECOVERY_STREAK[$p]:-0}|${PROFILE_QUARANTINED[$p]:-0}"; done)" node - <<'NODE'
const fs=require('fs');
const split=(s)=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const lines=split(process.env.PROFILES_JOINED);
let prev={}; try{prev=JSON.parse(fs.readFileSync(process.env.POOL_STATE_FILE,'utf8'));}catch{}
const profiles={};
for(const l of lines){
  const [k,f,c,r,q]=l.split('|');
  if(k) profiles[k]={
    failCount:Number(f||0),
    cooldownUntil:Number(c||0),
    recoveryStreak:Number(r||0),
    quarantined:Number(q||0)
  };
}
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
ALL_PROFILES_JOINED="$(printf '%s\n' "${ALL_PROFILES[@]:-}")" ACTIVE_JOINED="$(printf '%s\n' "${ACTIVE_PROFILES[@]:-}")" QUARANTINED_JOINED="$(printf '%s\n' "${QUARANTINED_PROFILES[@]:-}")" QUARANTINED_ACCOUNTS_JOINED="$(printf '%s\n' "${QUARANTINED_ACCOUNTS[@]:-}")" ORDER_INPUT_JOINED="$(printf '%s\n' "${ORDER_INPUT_PROFILES[@]:-}")" ACTIVE_ACCOUNT_COUNT="$active_account_count" FAILED_JOINED="$(printf '%s\n' "${FAILED_PROFILES[@]:-}")" WARN_JOINED="$(printf '%s\n' "${WARNINGS[@]:-}")" CRIT_JOINED="$(printf '%s\n' "${CRITICALS[@]:-}")" EXP_JOINED="$(printf '%s\n' "${EXPIRING_PROFILES[@]:-}")" RELOGIN_JOINED="$(printf '%s\n' "${RELOGIN_CMDS[@]:-}")" \
EMAIL_MAP_JOINED="$(for k in "${!PROFILE_EMAIL_MAP[@]}"; do echo "$k=${PROFILE_EMAIL_MAP[$k]}"; done)" SCORE_JOINED="$(for k in "${!PROFILE_SCORE[@]}"; do echo "$k=${PROFILE_SCORE[$k]}"; done)" DRY_RUN="$DRY_RUN" node - <<'NODE'
const fs=require('fs');
const split=s=>String(s||'').split('\n').map(x=>x.trim()).filter(Boolean);
const mapFrom=(s)=>{const o={};for(const l of split(s)){const i=l.indexOf('=');if(i>0)o[l.slice(0,i).trim()]=l.slice(i+1).trim();}return o;};
const failedRaw=split(process.env.FAILED_JOINED);
const emailMap=mapFrom(process.env.EMAIL_MAP_JOINED); const scoreMap=mapFrom(process.env.SCORE_JOINED);
const state=String(process.env.STATE||'');
const failed=(state==='Healthy' || state==='Recovered') ? [] : failedRaw;
const report={
  ts:process.env.TS_UTC,
  state,
  anomalyClass:process.env.ANOMALY_CLASS,
  provider:process.env.PROVIDER,
  discoveredProfiles:split(process.env.ALL_PROFILES_JOINED),
  discoveredCount:Number(process.env.PROFILE_COUNT||0),
  activeProfiles:split(process.env.ACTIVE_JOINED),
  activeProfileCount:split(process.env.ACTIVE_JOINED).length,
  activeAccountCount:Number(process.env.ACTIVE_ACCOUNT_COUNT||0),
  quarantinedProfiles:split(process.env.QUARANTINED_JOINED),
  quarantinedAccounts:split(process.env.QUARANTINED_ACCOUNTS_JOINED),
  orderInputProfiles:split(process.env.ORDER_INPUT_JOINED),
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
log "active profiles: ${#ACTIVE_PROFILES[@]} | active accounts: ${active_account_count:-0} | quarantined: ${#QUARANTINED_PROFILES[@]}"
log "failed profiles: ${FAILED_PROFILES[*]:-none}"
log "warnings: ${WARNINGS[*]:-none}"
log "criticals: ${CRITICALS[*]:-none}"
log "sync: $sync_note"
log "report: $LATEST_JSON"

# alerting (dedup + burst + hourly remind)
if [[ "$DRY_RUN" != "1" ]]; then
  level="PASS"; ((exit_code==2)) && level="CRITICAL"; ((exit_code==1)) && level="WARN"
  # hard guard: healthy/recovered must never alert as warning/critical
  if [[ "$state" == "Healthy" || "$state" == "Recovered" ]]; then
    level="PASS"
  fi
  failed_csv="none"
  if ((${#FAILED_PROFILES[@]} > 0)); then failed_csv=""; for fp in "${FAILED_PROFILES[@]}"; do failed_csv+="$(profile_display "$fp"), "; done; failed_csv="${failed_csv%, }"; fi
  reason="无"; ((${#CRITICALS[@]} > 0)) && reason="$(printf '%s; ' "${CRITICALS[@]}"|sed 's/; $//')"; ((${#CRITICALS[@]}==0 && ${#WARNINGS[@]}>0)) && reason="$(printf '%s; ' "${WARNINGS[@]}"|sed 's/; $//')"
  [[ "$level" == "PASS" ]] && icon="✅" && level_cn="健康" && title="[恢复/正常]"
  [[ "$level" == "WARN" ]] && icon="⚠️" && level_cn="预警" && title="[异常]"
  [[ "$level" == "CRITICAL" ]] && icon="🚨" && level_cn="严重" && title="[严重异常]"
  action_line="无"; ((${#RELOGIN_CMDS[@]} > 0)) && action_line="请仅重登失效账号（见报告 reloginCommands）"
  msg="${icon} ${title} OpenClaw 健康检查（${PROVIDER}）\n状态：${level_cn} (${level})\n阶段：${state}\n账号数：${#ALL_PROFILES[@]}\n失效账号：${failed_csv}\n异常原因：${reason}\n处理建议：${action_line}\n报告：${LATEST_JSON}"

  prev_level="PASS"; prev_alert_ts=0; prev_signature=""
  if [[ -f "$ALERT_STATE_FILE" ]]; then
    prev_level="$(node -e "const fs=require('fs');try{const o=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(String(o.level||'PASS'));}catch{process.stdout.write('PASS')}" "$ALERT_STATE_FILE")"
    prev_alert_ts="$(node -e "const fs=require('fs');try{const o=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(String(Number(o.lastAlertTs||0)));}catch{process.stdout.write('0')}" "$ALERT_STATE_FILE")"
    prev_signature="$(node -e "const fs=require('fs');try{const o=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(String(o.signature||''));}catch{process.stdout.write('')}" "$ALERT_STATE_FILE")"
  fi
  signature="$level|$ANOMALY_CLASS|$failed_csv"
  send_once(){ openclaw message send --channel "$TELEGRAM_CHANNEL" --target "$TELEGRAM_TARGET" --message "$1" >/dev/null 2>&1 || true; }

  # Reduce noise: optional suppression when warning is only cooldown-active signals
  cooldown_only=0
  if [[ "$ALERT_SUPPRESS_COOLDOWN_ONLY" == "1" && "$level" == "WARN" && ${#CRITICALS[@]} -eq 0 && ${#WARNINGS[@]} -gt 0 ]]; then
    cooldown_only=1
    for w in "${WARNINGS[@]}"; do
      [[ "$w" == cooldown\ active:* ]] || { cooldown_only=0; break; }
    done
  fi

  if [[ "$cooldown_only" == "1" ]]; then
    : # suppress cooldown-only warnings to avoid alert spam
  elif [[ "$level" != "PASS" ]]; then
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
