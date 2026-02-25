#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="${OCX_BASE_DIR:-/data/openclaw}"
ENV_FILE="${OCX_ENV_FILE:-/etc/openclaw-healthcheck.env}"
BOOTSTRAP_LANG="${OCX_BOOTSTRAP_LANG:-en}"

echo "[bootstrap] root=$ROOT_DIR"
echo "[bootstrap] base=$BASE_DIR"
echo "[bootstrap] env=$ENV_FILE"
echo "[bootstrap] lang=$BOOTSTRAP_LANG"

mkdir -p "$BASE_DIR/scripts" "$BASE_DIR/reports" "$BASE_DIR/run" "$BASE_DIR/config" "$BASE_DIR/systemd"

cp "$ROOT_DIR"/scripts/*.sh "$BASE_DIR/scripts/"
chmod +x "$BASE_DIR"/scripts/*.sh
cp -f "$ROOT_DIR"/systemd/*.service "$BASE_DIR/systemd/" || true
cp -f "$ROOT_DIR"/systemd/*.timer "$BASE_DIR/systemd/" || true
cp -n "$ROOT_DIR/config/openai-codex-auth-map.env.example" "$BASE_DIR/config/openai-codex-auth-map.env" || true

if [[ ! -f "$ENV_FILE" ]]; then
  mkdir -p "$(dirname "$ENV_FILE")"
  TEMPLATE="$ROOT_DIR/config/public-safe.env.example"
  if [[ "$BOOTSTRAP_LANG" == "zh" || "$BOOTSTRAP_LANG" == "zh-CN" || "$BOOTSTRAP_LANG" == "zh_cn" ]]; then
    TEMPLATE="$ROOT_DIR/config/public-safe.env.example.zh-CN"
  fi
  cp "$TEMPLATE" "$ENV_FILE"
  sed -i "s#^OCX_BASE_DIR=.*#OCX_BASE_DIR=$BASE_DIR#" "$ENV_FILE"
  echo "[bootstrap] created $ENV_FILE from template: $(basename "$TEMPLATE")"
else
  echo "[bootstrap] keep existing env: $ENV_FILE"
fi

if command -v systemctl >/dev/null 2>&1 && [[ "$(id -u)" == "0" ]]; then
  cp -f "$BASE_DIR/systemd/openclaw-healthcheck.service" /etc/systemd/system/
  cp -f "$BASE_DIR/systemd/openclaw-healthcheck.timer" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now openclaw-healthcheck.timer
  systemctl start openclaw-healthcheck.service || true
  echo "[bootstrap] systemd timer enabled"
else
  cat <<EOF
[bootstrap] systemd not auto-enabled (need root). Run manually:
  sudo cp $BASE_DIR/systemd/openclaw-healthcheck.service /etc/systemd/system/
  sudo cp $BASE_DIR/systemd/openclaw-healthcheck.timer /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now openclaw-healthcheck.timer
EOF
fi

echo "[bootstrap] done"
echo "[next] edit $ENV_FILE and replace placeholders (especially OCX_NOTIFY_TARGET)."
