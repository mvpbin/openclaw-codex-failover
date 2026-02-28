#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
REPORT_FILE="${OCX_REPORT_FILE:-$BASE_DIR/reports/openai_codex_health_latest.json}"
HEALTHCHECK_SCRIPT="${OCX_HEALTHCHECK_SCRIPT:-$BASE_DIR/scripts/healthcheck_openai_codex_pool.sh}"
MAX_STALE_SECONDS="${OCX_MAX_STALE_SECONDS:-1800}"
TRY_RESTART_TIMER="${OCX_TRY_RESTART_TIMER:-1}"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

if [[ ! "$MAX_STALE_SECONDS" =~ ^[0-9]+$ ]]; then
  log "invalid OCX_MAX_STALE_SECONDS=$MAX_STALE_SECONDS"
  exit 2
fi

if [[ ! -f "$REPORT_FILE" ]]; then
  log "health report missing: $REPORT_FILE"
  log "running healthcheck now..."
  "$HEALTHCHECK_SCRIPT"
  log "recovered: generated fresh report"
  exit 0
fi

last_mtime="$(stat -c %Y "$REPORT_FILE")"
now_ts="$(date +%s)"
age=$((now_ts - last_mtime))

if (( age <= MAX_STALE_SECONDS )); then
  log "healthy: report age ${age}s <= ${MAX_STALE_SECONDS}s"
  exit 0
fi

log "stale detected: report age ${age}s > ${MAX_STALE_SECONDS}s"
log "forcing one healthcheck run..."
"$HEALTHCHECK_SCRIPT"

new_mtime="$(stat -c %Y "$REPORT_FILE")"
new_age=$(( $(date +%s) - new_mtime ))

if (( new_age > MAX_STALE_SECONDS )); then
  log "report still stale after force-run (${new_age}s)"
  if [[ "$TRY_RESTART_TIMER" == "1" ]] && command -v systemctl >/dev/null 2>&1; then
    log "attempting timer/service restart..."
    systemctl restart openclaw-healthcheck.timer || true
    systemctl start openclaw-healthcheck.service || true
    sleep 2
    newest_mtime="$(stat -c %Y "$REPORT_FILE")"
    newest_age=$(( $(date +%s) - newest_mtime ))
    if (( newest_age <= MAX_STALE_SECONDS )); then
      log "recovered after timer/service restart"
      exit 0
    fi
  fi
  log "unrecovered stale report, manual check needed"
  exit 1
fi

log "recovered: report freshness restored (${new_age}s)"
