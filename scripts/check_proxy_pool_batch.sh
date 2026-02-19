#!/usr/bin/env bash
set -euo pipefail

# Concurrent proxy clean checks for first N profiles in map.
# Usage:
#   check_proxy_pool_batch.sh [limit=50] [concurrency=5]

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
MAP_FILE="${OCX_SOCKS5_MAP_FILE:-$BASE_DIR/config/openai-codex-socks5-map.env}"
CHECK_SCRIPT="$BASE_DIR/scripts/check_socks5_proxy_clean.sh"
LIMIT="${1:-50}"
CONCURRENCY="${2:-${OCX_PROXY_CHECK_CONCURRENCY:-5}}"

if [[ ! -f "$MAP_FILE" ]]; then
  echo "map file not found: $MAP_FILE" >&2
  exit 2
fi
if [[ ! -x "$CHECK_SCRIPT" ]]; then
  echo "check script not executable: $CHECK_SCRIPT" >&2
  exit 2
fi

tmp_profiles="$(mktemp)"
tmp_report="${BASE_DIR}/reports/proxy-batch-$(date +%Y%m%dT%H%M%SZ).log"
awk -F= '/^openai-codex:/{print $1}' "$MAP_FILE" | head -n "$LIMIT" > "$tmp_profiles"

run_one(){
  local profile="$1"
  local out rc
  out="$($CHECK_SCRIPT "$profile" 2>&1)" && rc=0 || rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "PASS $profile :: $(echo "$out" | tail -n1)"
  else
    echo "FAIL $profile :: $(echo "$out" | tail -n1)"
  fi
}

export -f run_one
export CHECK_SCRIPT

cat "$tmp_profiles" | xargs -I{} -P "$CONCURRENCY" bash -lc 'run_one "$@"' _ {} | tee "$tmp_report"

pass=$(grep -c '^PASS ' "$tmp_report" || true)
fail=$(grep -c '^FAIL ' "$tmp_report" || true)
echo "summary: pass=$pass fail=$fail report=$tmp_report"