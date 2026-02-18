#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"

type_out() {
  local s="$1"
  printf "$ %s\n" "$s"
  sleep 0.6
}

run() {
  local s="$1"
  type_out "$s"
  bash -lc "$s" || true
  echo
  sleep 0.8
}

echo "OpenClaw Codex Failover - Quick Validation Demo"
sleep 1

type_out "export OCX_BASE_DIR=${BASE_DIR}"
export OCX_BASE_DIR="$BASE_DIR"
echo
sleep 0.8

run "$OCX_BASE_DIR/scripts/preflight_openai_codex_failover.sh | sed -n '1,18p'"
run "systemctl start openclaw-healthcheck.service || true"
run "cat $OCX_BASE_DIR/reports/openai_codex_health_latest.json | sed -n '1,80p'"
run "SIMULATE_UNUSABLE=openai-codex:acc03 $OCX_BASE_DIR/scripts/healthcheck_openai_codex_pool.sh --dry-run >/tmp/ocx_demo_dryrun.log 2>&1 || true; tail -n 12 /tmp/ocx_demo_dryrun.log"

echo "Demo complete."
