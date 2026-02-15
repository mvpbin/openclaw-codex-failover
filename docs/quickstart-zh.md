# 快速开始（超简版，可换路径）

## 1) 选择部署路径

```bash
# 推荐（有 /data）
export OCX_BASE_DIR=/data/openclaw

# 或默认兼容
# export OCX_BASE_DIR=$HOME/.openclaw/openclaw-tools
```

## 2) 一键安装

```bash
sudo bash -lc '
set -e
: "${OCX_BASE_DIR:=/data/openclaw}"
mkdir -p "$OCX_BASE_DIR/scripts" "$OCX_BASE_DIR/reports" "$OCX_BASE_DIR/systemd"
cp scripts/*.sh "$OCX_BASE_DIR/scripts/"
cp systemd/* "$OCX_BASE_DIR/systemd/"
chmod +x "$OCX_BASE_DIR/scripts"/*.sh
cp "$OCX_BASE_DIR/systemd/openclaw-healthcheck.service" /etc/systemd/system/
cp "$OCX_BASE_DIR/systemd/openclaw-healthcheck.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now openclaw-healthcheck.timer
'
```

## 3) 手动跑一次

```bash
sudo systemctl start openclaw-healthcheck.service
```

## 4) 看结果

```bash
cat ${OCX_BASE_DIR:-/data/openclaw}/reports/openai_codex_health_latest.json
```

- `discoveredCount`：自动发现账号总数（无限制）
- `exitCode=0` => PASS
- `exitCode=1` => WARN
- `exitCode=2` => CRITICAL

## 5) 验证 Telegram 摘要

```bash
${OCX_BASE_DIR:-/data/openclaw}/scripts/healthcheck_openai_codex_pool.sh
```

## 6) 无破坏模拟

```bash
SIMULATE_UNUSABLE=openai-codex:acc03 ${OCX_BASE_DIR:-/data/openclaw}/scripts/healthcheck_openai_codex_pool.sh || true
```

## 7) 推荐：启用环境配置文件

```bash
sudo cp openclaw-healthcheck.env.example /etc/openclaw-healthcheck.env
sudo systemctl daemon-reload
sudo systemctl restart openclaw-healthcheck.timer
```

## 8) 只检查不发消息（dry-run）

```bash
${OCX_BASE_DIR:-/data/openclaw}/scripts/healthcheck_openai_codex_pool.sh --dry-run
```
