#!/usr/bin/env bash
set -euo pipefail

DEFAULT_ENV_FILE="/etc/openclaw-healthcheck.env"
if [[ -f "$DEFAULT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEFAULT_ENV_FILE"
fi

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
RUN_USER="${OCX_RUN_USER:-root}"
CODEX_AUTH_PATH="${OCX_CODEX_AUTH_PATH:-/root/.codex/auth.json}"

ok=0; warn=0; err=0
pass(){ echo "✅ $*"; ok=$((ok+1)); }
warnf(){ echo "⚠️  $*"; warn=$((warn+1)); }
fail(){ echo "❌ $*"; err=$((err+1)); }

check_cmd(){ command -v "$1" >/dev/null 2>&1 && pass "command exists: $1" || fail "missing command: $1"; }

echo "== OpenClaw Codex Failover Preflight =="
check_cmd openclaw
check_cmd node
check_cmd bash
check_cmd codex

[[ -d "$BASE_DIR" ]] && pass "base dir exists: $BASE_DIR" || warnf "base dir missing (install will create): $BASE_DIR"
for s in healthcheck_openai_codex_pool.sh repair_openai_codex_pool.sh onboard_openai_codex_profile.sh import_codex_auth_to_openclaw.sh sync_openclaw_auth_order.sh; do
  [[ -x "$BASE_DIR/scripts/$s" ]] && pass "script executable: $BASE_DIR/scripts/$s" || fail "script missing/not executable: $BASE_DIR/scripts/$s"
done

if id "$RUN_USER" >/dev/null 2>&1; then
  pass "run user exists: $RUN_USER"
else
  warnf "run user not found: $RUN_USER (if service uses another user, this may be fine)"
fi

if systemctl list-unit-files | grep -q '^openclaw-healthcheck.timer'; then
  pass "timer unit installed"
else
  warnf "timer unit not installed"
fi

if systemctl is-enabled openclaw-healthcheck.timer >/dev/null 2>&1; then
  pass "timer enabled"
else
  warnf "timer not enabled"
fi

if [[ -f "$CODEX_AUTH_PATH" ]]; then
  pass "codex auth file found: $CODEX_AUTH_PATH"
else
  warnf "codex auth file not found: $CODEX_AUTH_PATH"
fi

if openclaw models status --json >/dev/null 2>&1; then
  pass "openclaw models status works"
else
  fail "openclaw models status failed"
fi

echo "\nSummary: ok=$ok warn=$warn err=$err"
(( err == 0 ))