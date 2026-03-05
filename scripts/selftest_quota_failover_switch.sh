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
AUTH_PROFILES_PATH="${OCX_AUTH_PROFILES_PATH:-/root/.openclaw/agents/${AGENT}/agent/auth-profiles.json}"
HEALTHCHECK_SCRIPT="${OCX_HEALTHCHECK_SCRIPT:-$BASE_DIR/scripts/healthcheck_openai_codex_pool.sh}"
TIMEOUT_SECONDS="${OCX_SELFTEST_TIMEOUT_SECONDS:-60}"
INTERVAL_SECONDS="${OCX_SELFTEST_INTERVAL_SECONDS:-2}"
MODE="${OCX_SELFTEST_MODE:-shadow}" # shadow | live

usage() {
  cat <<USAGE
Usage: $0 [--mode shadow|live] [--timeout seconds] [--interval seconds]

shadow: run against temporary auth/run/report copies (safe default)
live:   run against current runtime files (will change current order state)
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECONDS="${2:-}"
      shift 2
      ;;
    --interval)
      INTERVAL_SECONDS="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$MODE" != "shadow" && "$MODE" != "live" ]]; then
  echo "invalid --mode: $MODE" >&2
  exit 2
fi
if ! [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ && "$TIMEOUT_SECONDS" -gt 0 ]]; then
  echo "invalid --timeout: $TIMEOUT_SECONDS" >&2
  exit 2
fi
if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ && "$INTERVAL_SECONDS" -gt 0 ]]; then
  echo "invalid --interval: $INTERVAL_SECONDS" >&2
  exit 2
fi
if [[ ! -x "$HEALTHCHECK_SCRIPT" ]]; then
  echo "healthcheck script not executable: $HEALTHCHECK_SCRIPT" >&2
  exit 1
fi
if [[ ! -f "$AUTH_PROFILES_PATH" ]]; then
  echo "auth profiles not found: $AUTH_PROFILES_PATH" >&2
  exit 1
fi

get_head_profile() {
  local auth_path="$1"
  AUTH_PROFILES_PATH="$auth_path" PROVIDER="$PROVIDER" node - <<'NODE'
const fs=require('fs');
const p=process.env.AUTH_PROFILES_PATH;
const provider=String(process.env.PROVIDER||'openai-codex');
let j={};
try{j=JSON.parse(fs.readFileSync(p,'utf8'));}catch{}
const order=(j&&j.order&&Array.isArray(j.order[provider]))?j.order[provider]:[];
if(order.length>0) process.stdout.write(String(order[0]));
NODE
}

run_once() {
  local auth_path="$1"
  local run_dir="$2"
  local report_dir="$3"
  OCX_AUTH_PROFILES_PATH="$auth_path" \
  OCX_SKIP_DEFAULT_ENV=1 \
  OCX_PROFILE_SOURCE="auth-store" \
  OCX_ORDER_WRITE_MODE="auth-file" \
  OCX_RUN_DIR="$run_dir" \
  OCX_REPORT_DIR="$report_dir" \
  OCX_CONFIG_HISTORY_DIR="$run_dir/history" \
  OCX_DRY_RUN=1 \
  OCX_DISABLE_PROBES=1 \
  "$HEALTHCHECK_SCRIPT" --simulate-unusable "$TARGET_PROFILE" >/dev/null 2>&1 || true
}

if [[ "$MODE" == "shadow" ]]; then
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  TEST_AUTH="$TMP_DIR/auth-profiles.json"
  TEST_RUN_DIR="$TMP_DIR/run"
  TEST_REPORT_DIR="$TMP_DIR/reports"
  mkdir -p "$TEST_RUN_DIR" "$TEST_REPORT_DIR"
  cp "$AUTH_PROFILES_PATH" "$TEST_AUTH"
  # Normalize expiry in shadow mode so test result focuses on injected failure,
  # not historical expired tokens in production snapshots.
  AUTH_PROFILES_PATH="$TEST_AUTH" node - <<'NODE'
const fs=require('fs');
const p=process.env.AUTH_PROFILES_PATH;
let j={};
try{j=JSON.parse(fs.readFileSync(p,'utf8'));}catch{process.exit(1)}
const now=Date.now();
for(const k of Object.keys(j.profiles||{})){
  const row=j.profiles[k]||{};
  row.expires=now + 24*3600*1000;
  j.profiles[k]=row;
}
fs.writeFileSync(p, JSON.stringify(j,null,2));
NODE
else
  TEST_AUTH="$AUTH_PROFILES_PATH"
  TEST_RUN_DIR="${OCX_RUN_DIR:-$BASE_DIR/run}"
  TEST_REPORT_DIR="${OCX_REPORT_DIR:-$BASE_DIR/reports}"
  mkdir -p "$TEST_RUN_DIR" "$TEST_REPORT_DIR"
fi

TARGET_PROFILE="$(get_head_profile "$TEST_AUTH")"
if [[ -z "$TARGET_PROFILE" ]]; then
  echo "selftest failed: unable to resolve current head profile" >&2
  exit 1
fi

echo "selftest mode: $MODE"
echo "target profile: $TARGET_PROFILE"

start_ts="$(date +%s)"
deadline=$((start_ts + TIMEOUT_SECONDS))
switched=0
new_head=""

while (( $(date +%s) <= deadline )); do
  run_once "$TEST_AUTH" "$TEST_RUN_DIR" "$TEST_REPORT_DIR"
  new_head="$(get_head_profile "$TEST_AUTH")"
  if [[ -n "$new_head" && "$new_head" != "$TARGET_PROFILE" ]]; then
    switched=1
    break
  fi
  sleep "$INTERVAL_SECONDS"
done

elapsed=$(( $(date +%s) - start_ts ))

if (( switched == 1 )); then
  echo "PASS: failover switched head within ${elapsed}s"
  echo "before: $TARGET_PROFILE"
  echo "after:  $new_head"
  if [[ "$MODE" == "shadow" ]]; then
    echo "report: $TEST_REPORT_DIR/openai_codex_health_latest.json"
  fi
  exit 0
fi

echo "FAIL: failover did not switch head within ${TIMEOUT_SECONDS}s" >&2
echo "head remains: ${new_head:-<empty>}" >&2
exit 1
